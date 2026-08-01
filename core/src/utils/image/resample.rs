use super::{Rect, RgbaImage};

pub(super) fn smooth(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
    if src_rect.width > dst_rect.width || src_rect.height > dst_rect.height {
        area(src, src_rect, dst, dst_rect);
    } else {
        bilinear(src, src_rect, dst, dst_rect);
    }
}

fn area(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
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
                    let pixel = pixel(src, sx, sy);
                    let alpha = pixel[3] as f32 / 255.0;
                    alpha_sum += alpha * weight;
                    red_sum += pixel[0] as f32 * alpha * weight;
                    green_sum += pixel[1] as f32 * alpha * weight;
                    blue_sum += pixel[2] as f32 * alpha * weight;
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
            write_pixel(dst, dst_rect.x + dx, dst_rect.y + dy, sample);
        }
    }
}

fn bilinear(src: &RgbaImage, src_rect: Rect, dst: &mut RgbaImage, dst_rect: Rect) {
    for dy in 0..dst_rect.height {
        let sy = (src_rect.y as f32
            + (dy as f32 + 0.5) * src_rect.height as f32 / dst_rect.height as f32
            - 0.5)
            .clamp(src_rect.y as f32, (src_rect.y + src_rect.height - 1) as f32);
        let y0 = sy.floor() as u32;
        let y1 = (y0 + 1).min(src_rect.y + src_rect.height - 1);
        let wy = sy - y0 as f32;

        for dx in 0..dst_rect.width {
            let sx = (src_rect.x as f32
                + (dx as f32 + 0.5) * src_rect.width as f32 / dst_rect.width as f32
                - 0.5)
                .clamp(src_rect.x as f32, (src_rect.x + src_rect.width - 1) as f32);
            let x0 = sx.floor() as u32;
            let x1 = (x0 + 1).min(src_rect.x + src_rect.width - 1);
            let wx = sx - x0 as f32;
            let sample = blend4(src, x0, y0, x1, y1, wx, wy);
            write_pixel(dst, dst_rect.x + dx, dst_rect.y + dy, sample);
        }
    }
}

fn blend4(src: &RgbaImage, x0: u32, y0: u32, x1: u32, y1: u32, wx: f32, wy: f32) -> [u8; 4] {
    let pixels = [
        pixel(src, x0, y0),
        pixel(src, x1, y0),
        pixel(src, x0, y1),
        pixel(src, x1, y1),
    ];
    let weights = [
        (1.0 - wx) * (1.0 - wy),
        wx * (1.0 - wy),
        (1.0 - wx) * wy,
        wx * wy,
    ];
    let alpha = pixels
        .iter()
        .zip(weights)
        .map(|(pixel, weight)| pixel[3] as f32 * weight)
        .sum::<f32>();
    if alpha <= 0.0 {
        return [0, 0, 0, 0];
    }

    let mut output = [0; 4];
    for channel in 0..3 {
        let premultiplied = pixels
            .iter()
            .zip(weights)
            .map(|(pixel, weight)| pixel[channel] as f32 * pixel[3] as f32 / 255.0 * weight)
            .sum::<f32>();
        output[channel] = (premultiplied * 255.0 / alpha).round().clamp(0.0, 255.0) as u8;
    }
    output[3] = alpha.round().clamp(0.0, 255.0) as u8;
    output
}

fn pixel(image: &RgbaImage, x: u32, y: u32) -> [u8; 4] {
    let offset = ((y * image.width + x) * 4) as usize;
    image.pixels[offset..offset + 4]
        .try_into()
        .unwrap_or([0, 0, 0, 0])
}

fn write_pixel(image: &mut RgbaImage, x: u32, y: u32, pixel: [u8; 4]) {
    let offset = ((y * image.width + x) * 4) as usize;
    image.pixels[offset..offset + 4].copy_from_slice(&pixel);
}
