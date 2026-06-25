//! Shared image utilities for backend-side PNG/RGBA processing.
//!
//! Mirrors Sparkle's transparent crop/pad pass, but runs before the PNG is
//! stored in Rust's disk cache so Flutter can decode cached bytes directly.

use std::io::Cursor;

pub(crate) const DEFAULT_ICON_SIZE: u32 = 256;
const MAX_ICON_SIZE: u32 = 256;
const DEFAULT_ICON_BORDER: u32 = 24;
const ALPHA_THRESHOLD: u8 = 10;
const CROP_EDGE_MARGIN: u32 = 2;

pub(crate) fn normalize_desktop_icon(bytes: &[u8], size: u32) -> Option<Vec<u8>> {
    let image = decode_png_rgba(bytes)?;
    crop_and_pad_transparent(&image, size)
        .and_then(|normalized| encode_png_rgba(&normalized))
        .or_else(|| encode_png_rgba(&image))
}

struct RgbaImage {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

fn decode_png_rgba(bytes: &[u8]) -> Option<RgbaImage> {
    let mut decoder = png::Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(
        png::Transformations::EXPAND | png::Transformations::ALPHA | png::Transformations::STRIP_16,
    );
    let mut reader = decoder.read_info().ok()?;
    let mut pixels = vec![0; reader.output_buffer_size()?];
    let info = reader.next_frame(&mut pixels).ok()?;
    pixels.truncate(info.buffer_size());
    match info.color_type {
        png::ColorType::Rgba => Some(RgbaImage {
            width: info.width,
            height: info.height,
            pixels,
        }),
        png::ColorType::Rgb => Some(RgbaImage {
            width: info.width,
            height: info.height,
            pixels: rgb_to_rgba(&pixels),
        }),
        png::ColorType::Grayscale => Some(RgbaImage {
            width: info.width,
            height: info.height,
            pixels: gray_to_rgba(&pixels),
        }),
        png::ColorType::GrayscaleAlpha => Some(RgbaImage {
            width: info.width,
            height: info.height,
            pixels: gray_alpha_to_rgba(&pixels),
        }),
        png::ColorType::Indexed => None,
    }
}

fn rgb_to_rgba(src: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(src.len() / 3 * 4);
    for px in src.chunks_exact(3) {
        out.extend_from_slice(&[px[0], px[1], px[2], 255]);
    }
    out
}

fn gray_to_rgba(src: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(src.len() * 4);
    for gray in src {
        out.extend_from_slice(&[*gray, *gray, *gray, 255]);
    }
    out
}

fn gray_alpha_to_rgba(src: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(src.len() / 2 * 4);
    for px in src.chunks_exact(2) {
        out.extend_from_slice(&[px[0], px[0], px[0], px[1]]);
    }
    out
}

fn content_bounds(src: &RgbaImage) -> Option<Rect> {
    let mut top = src.height;
    let mut bottom = 0;
    let mut left = src.width;
    let mut right = 0;

    for y in 0..src.height {
        for x in 0..src.width {
            let alpha = src.pixels[((y * src.width + x) * 4 + 3) as usize];
            if alpha > ALPHA_THRESHOLD {
                left = left.min(x);
                right = right.max(x);
                top = top.min(y);
                bottom = bottom.max(y);
            }
        }
    }

    if right < left || bottom < top {
        return None;
    }

    Some(Rect {
        x: left,
        y: top,
        width: right - left + 1,
        height: bottom - top + 1,
    })
}

fn crop_and_pad_transparent(src: &RgbaImage, size: u32) -> Option<RgbaImage> {
    let size = size.clamp(1, MAX_ICON_SIZE);
    let border = scaled_border(size);
    let bounds = content_bounds(src)?;
    let mut left = bounds.x;
    let mut top = bounds.y;
    let mut right = bounds.x + bounds.width - 1;
    let mut bottom = bounds.y + bounds.height - 1;

    left = left.saturating_sub(CROP_EDGE_MARGIN);
    top = top.saturating_sub(CROP_EDGE_MARGIN);
    right = (right + CROP_EDGE_MARGIN).min(src.width - 1);
    bottom = (bottom + CROP_EDGE_MARGIN).min(src.height - 1);

    let crop_width = right - left + 1;
    let crop_height = bottom - top + 1;
    let content_size = size - 2 * border;

    let (draw_width, draw_height, offset_x, offset_y) = if crop_width > crop_height {
        let draw_height = (content_size * crop_height).max(1) / crop_width;
        (
            content_size,
            draw_height.max(1),
            border,
            border + (content_size - draw_height.max(1)) / 2,
        )
    } else {
        let draw_width = (content_size * crop_width).max(1) / crop_height;
        (
            draw_width.max(1),
            content_size,
            border + (content_size - draw_width.max(1)) / 2,
            border,
        )
    };

    let mut out = RgbaImage {
        width: size,
        height: size,
        pixels: vec![0; (size * size * 4) as usize],
    };

    let src_rect = Rect {
        x: left,
        y: top,
        width: crop_width,
        height: crop_height,
    };
    let dst_rect = Rect {
        x: offset_x,
        y: offset_y,
        width: draw_width,
        height: draw_height,
    };
    resample_icon(src, src_rect, &mut out, dst_rect);
    Some(out)
}

fn scaled_border(size: u32) -> u32 {
    ((size * DEFAULT_ICON_BORDER + DEFAULT_ICON_SIZE / 2) / DEFAULT_ICON_SIZE).min(size / 3)
}

#[derive(Clone, Copy)]
struct Rect {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

fn resample_icon(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
    if src_rect.width > dst_rect.width || src_rect.height > dst_rect.height {
        resample_area(src, src_rect, dst, dst_rect);
    } else {
        resample_bilinear(src, src_rect, dst, dst_rect);
    }
}

fn resample_area(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
    let scale_x = src_rect.width as f32 / dst_rect.width as f32;
    let scale_y = src_rect.height as f32 / dst_rect.height as f32;
    let src_right = src_rect.x + src_rect.width;
    let src_bottom = src_rect.y + src_rect.height;

    for dy in 0..dst_rect.height {
        let sy0 = src_rect.y as f32 + dy as f32 * scale_y;
        let sy1 = src_rect.y as f32 + (dy + 1) as f32 * scale_y;
        let y_start = sy0.floor().max(src_rect.y as f32) as u32;
        let y_end = sy1.ceil().min(src_bottom as f32) as u32;

        for dx in 0..dst_rect.width {
            let sx0 = src_rect.x as f32 + dx as f32 * scale_x;
            let sx1 = src_rect.x as f32 + (dx + 1) as f32 * scale_x;
            let x_start = sx0.floor().max(src_rect.x as f32) as u32;
            let x_end = sx1.ceil().min(src_right as f32) as u32;

            let mut alpha_sum = 0.0;
            let mut red_sum = 0.0;
            let mut green_sum = 0.0;
            let mut blue_sum = 0.0;
            let mut area_sum = 0.0;

            for sy in y_start..y_end {
                let overlap_y = ((sy + 1) as f32).min(sy1) - (sy as f32).max(sy0);
                if overlap_y <= 0.0 {
                    continue;
                }
                for sx in x_start..x_end {
                    let overlap_x = ((sx + 1) as f32).min(sx1) - (sx as f32).max(sx0);
                    if overlap_x <= 0.0 {
                        continue;
                    }
                    let weight = overlap_x * overlap_y;
                    let px = pixel(src, sx, sy);
                    let alpha = px[3] as f32 / 255.0;
                    alpha_sum += alpha * weight;
                    red_sum += px[0] as f32 * alpha * weight;
                    green_sum += px[1] as f32 * alpha * weight;
                    blue_sum += px[2] as f32 * alpha * weight;
                    area_sum += weight;
                }
            }

            let sample = if alpha_sum <= 0.0 || area_sum <= 0.0 {
                [0, 0, 0, 0]
            } else {
                [
                    (red_sum / alpha_sum).round().clamp(0.0, 255.0) as u8,
                    (green_sum / alpha_sum).round().clamp(0.0, 255.0) as u8,
                    (blue_sum / alpha_sum).round().clamp(0.0, 255.0) as u8,
                    (alpha_sum * 255.0 / area_sum).round().clamp(0.0, 255.0) as u8,
                ]
            };
            let offset = (((dst_rect.y + dy) * dst.width + dst_rect.x + dx) * 4) as usize;
            dst.pixels[offset..offset + 4].copy_from_slice(&sample);
        }
    }
}

fn resample_bilinear(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
    for dy in 0..dst_rect.height {
        let sy = src_rect.y as f32
            + (dy as f32 + 0.5) * src_rect.height as f32 / dst_rect.height as f32
            - 0.5;
        let y0 = sy
            .floor()
            .clamp(src_rect.y as f32, (src_rect.y + src_rect.height - 1) as f32)
            as u32;
        let y1 = (y0 + 1).min(src_rect.y + src_rect.height - 1);
        let wy = sy - sy.floor();

        for dx in 0..dst_rect.width {
            let sx = src_rect.x as f32
                + (dx as f32 + 0.5) * src_rect.width as f32 / dst_rect.width as f32
                - 0.5;
            let x0 = sx
                .floor()
                .clamp(src_rect.x as f32, (src_rect.x + src_rect.width - 1) as f32)
                as u32;
            let x1 = (x0 + 1).min(src_rect.x + src_rect.width - 1);
            let wx = sx - sx.floor();

            let sample =
                blend4_premultiplied(src, x0, y0, x1, y1, wx.clamp(0.0, 1.0), wy.clamp(0.0, 1.0));
            let offset = (((dst_rect.y + dy) * dst.width + dst_rect.x + dx) * 4) as usize;
            dst.pixels[offset..offset + 4].copy_from_slice(&sample);
        }
    }
}

fn blend4_premultiplied(
    src: &RgbaImage,
    x0: u32,
    y0: u32,
    x1: u32,
    y1: u32,
    wx: f32,
    wy: f32,
) -> [u8; 4] {
    let c00 = pixel(src, x0, y0);
    let c10 = pixel(src, x1, y0);
    let c01 = pixel(src, x0, y1);
    let c11 = pixel(src, x1, y1);
    let weights = [
        (1.0 - wx) * (1.0 - wy),
        wx * (1.0 - wy),
        (1.0 - wx) * wy,
        wx * wy,
    ];
    let pixels = [c00, c10, c01, c11];

    let alpha = pixels
        .iter()
        .zip(weights)
        .map(|(px, weight)| px[3] as f32 * weight)
        .sum::<f32>();
    if alpha <= 0.0 {
        return [0, 0, 0, 0];
    }

    let mut out = [0; 4];
    for i in 0..3 {
        let premultiplied = pixels
            .iter()
            .zip(weights)
            .map(|(px, weight)| px[i] as f32 * px[3] as f32 / 255.0 * weight)
            .sum::<f32>();
        out[i] = (premultiplied * 255.0 / alpha).round().clamp(0.0, 255.0) as u8;
    }
    out[3] = alpha.round().clamp(0.0, 255.0) as u8;
    out
}

fn pixel(src: &RgbaImage, x: u32, y: u32) -> [u8; 4] {
    let offset = ((y * src.width + x) * 4) as usize;
    src.pixels[offset..offset + 4]
        .try_into()
        .unwrap_or([0, 0, 0, 0])
}

fn encode_png_rgba(image: &RgbaImage) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut out, image.width, image.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder
            .write_header()
            .ok()?
            .write_image_data(&image.pixels)
            .ok()?;
    }
    Some(out)
}
