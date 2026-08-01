//! Shared image utilities for backend-side PNG/RGBA processing.
//!
//! Crops transparent padding and normalizes desktop icons before they enter
//! the disk cache, so Flutter can decode the cached bytes directly.

use std::io::Cursor;

mod resample;

pub(crate) const DEFAULT_ICON_SIZE: u32 = 256;
const MAX_ICON_SIZE: u32 = 256;
const DEFAULT_ICON_BORDER: u32 = 24;
const ALPHA_THRESHOLD: u8 = 10;
const TOTAL_EDGE_ENERGY_DIVISOR: u64 = 1_024;
const PEAK_EDGE_ENERGY_DIVISOR: u64 = 128;

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
    let mut columns = vec![0_u64; src.width as usize];
    let mut rows = vec![0_u64; src.height as usize];
    let mut total = 0_u64;

    for y in 0..src.height {
        for x in 0..src.width {
            let alpha = src.pixels[((y * src.width + x) * 4 + 3) as usize];
            // Squared alpha separates real thin strokes from broad, faint halos.
            let alpha = alpha.saturating_sub(ALPHA_THRESHOLD) as u64;
            let energy = alpha * alpha;
            columns[x as usize] += energy;
            rows[y as usize] += energy;
            total += energy;
        }
    }

    if total == 0 {
        return None;
    }

    let (left, right) = significant_range(&columns, total)?;
    let (top, bottom) = significant_range(&rows, total)?;

    Some(Rect {
        x: left as u32,
        y: top as u32,
        width: (right - left + 1) as u32,
        height: (bottom - top + 1) as u32,
    })
}

fn significant_range(energy: &[u64], total: u64) -> Option<(usize, usize)> {
    let mut left = energy.iter().position(|value| *value > 0)?;
    let mut right = energy.iter().rposition(|value| *value > 0)?;
    let peak = energy.iter().copied().max()?;
    let budget = (total / TOTAL_EDGE_ENERGY_DIVISOR).min(peak / PEAK_EDGE_ENERGY_DIVISOR);
    let mut discarded = 0_u64;

    while left < right && discarded.saturating_add(energy[left]) <= budget {
        discarded += energy[left];
        left += 1;
    }

    discarded = 0;
    while right > left && discarded.saturating_add(energy[right]) <= budget {
        discarded += energy[right];
        right -= 1;
    }

    Some((left, right))
}

fn crop_and_pad_transparent(src: &RgbaImage, size: u32) -> Option<RgbaImage> {
    let size = size.clamp(1, MAX_ICON_SIZE);
    let border = scaled_border(size);
    let bounds = content_bounds(src)?;
    let mut left = bounds.x;
    let mut top = bounds.y;
    let mut right = bounds.x + bounds.width - 1;
    let mut bottom = bounds.y + bounds.height - 1;
    let edge_margin = (bounds.width.max(bounds.height).saturating_div(64) + 1).min(2);

    left = left.saturating_sub(edge_margin);
    top = top.saturating_sub(edge_margin);
    right = (right + edge_margin).min(src.width - 1);
    bottom = (bottom + edge_margin).min(src.height - 1);

    let crop_width = right - left + 1;
    let crop_height = bottom - top + 1;
    let content_size = size - 2 * border;

    let (draw_width, draw_height) = if crop_width > crop_height {
        let draw_height = scaled_dimension(content_size, crop_height, crop_width);
        (content_size, draw_height)
    } else {
        let draw_width = scaled_dimension(content_size, crop_width, crop_height);
        (draw_width, content_size)
    };
    let offset_x = (size - draw_width) / 2;
    let offset_y = (size - draw_height) / 2;

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
    resample::smooth(src, src_rect, &mut out, dst_rect);
    Some(out)
}

fn scaled_dimension(max: u32, value: u32, basis: u32) -> u32 {
    (((u64::from(max) * u64::from(value) + u64::from(basis) / 2) / u64::from(basis)) as u32).max(1)
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
