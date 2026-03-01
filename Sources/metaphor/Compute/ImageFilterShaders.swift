import Foundation

/// GPU画像フィルタ用のMSLコンピュートシェーダーソース
enum ImageFilterShaders {

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FilterParams {
        uint width;
        uint height;
        float param1;
        float param2;
    };

    // MARK: - Threshold

    kernel void filter_threshold(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half4 c = inTex.read(gid);
        half luma = c.r * 0.299h + c.g * 0.587h + c.b * 0.114h;
        half val = luma >= half(params.param1) ? 1.0h : 0.0h;
        outTex.write(half4(val, val, val, c.a), gid);
    }

    // MARK: - Grayscale

    kernel void filter_gray(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half4 c = inTex.read(gid);
        half luma = c.r * 0.299h + c.g * 0.587h + c.b * 0.114h;
        outTex.write(half4(luma, luma, luma, c.a), gid);
    }

    // MARK: - Invert

    kernel void filter_invert(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half4 c = inTex.read(gid);
        outTex.write(half4(1.0h - c.r, 1.0h - c.g, 1.0h - c.b, c.a), gid);
    }

    // MARK: - Posterize

    kernel void filter_posterize(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half4 c = inTex.read(gid);
        half levels = half(params.param1 - 1.0);
        half r = round(c.r * levels) / levels;
        half g = round(c.g * levels) / levels;
        half b = round(c.b * levels) / levels;
        outTex.write(half4(r, g, b, c.a), gid);
    }

    // MARK: - Gaussian Blur (Horizontal)

    kernel void filter_gaussian_h(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        constant float *weights [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        int radius = int(params.param1);
        half4 sum = half4(0);
        for (int dx = -radius; dx <= radius; dx++) {
            int sx = clamp(int(gid.x) + dx, 0, int(params.width) - 1);
            half4 s = inTex.read(uint2(sx, gid.y));
            sum += s * half(weights[dx + radius]);
        }
        outTex.write(sum, gid);
    }

    // MARK: - Gaussian Blur (Vertical)

    kernel void filter_gaussian_v(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        constant float *weights [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        int radius = int(params.param1);
        half4 sum = half4(0);
        for (int dy = -radius; dy <= radius; dy++) {
            int sy = clamp(int(gid.y) + dy, 0, int(params.height) - 1);
            half4 s = inTex.read(uint2(gid.x, sy));
            sum += s * half(weights[dy + radius]);
        }
        outTex.write(sum, gid);
    }

    // MARK: - Erode (3x3 min)

    kernel void filter_erode(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half3 minVal = half3(1.0h);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int sx = clamp(int(gid.x) + dx, 0, int(params.width) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(params.height) - 1);
                half4 s = inTex.read(uint2(sx, sy));
                minVal = min(minVal, s.rgb);
            }
        }
        half4 orig = inTex.read(gid);
        outTex.write(half4(minVal, orig.a), gid);
    }

    // MARK: - Dilate (3x3 max)

    kernel void filter_dilate(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half3 maxVal = half3(0.0h);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int sx = clamp(int(gid.x) + dx, 0, int(params.width) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(params.height) - 1);
                half4 s = inTex.read(uint2(sx, sy));
                maxVal = max(maxVal, s.rgb);
            }
        }
        half4 orig = inTex.read(gid);
        outTex.write(half4(maxVal, orig.a), gid);
    }

    // MARK: - Edge Detect (Sobel 3x3)

    kernel void filter_edgeDetect(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;

        // Sobel kernels
        half gx = 0.0h, gy = 0.0h;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int sx = clamp(int(gid.x) + dx, 0, int(params.width) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(params.height) - 1);
                half4 s = inTex.read(uint2(sx, sy));
                half luma = s.r * 0.299h + s.g * 0.587h + s.b * 0.114h;

                // Gx kernel: [-1,0,1; -2,0,2; -1,0,1]
                half wx = half(dx) * (dy == 0 ? 2.0h : 1.0h);
                gx += luma * wx;

                // Gy kernel: [-1,-2,-1; 0,0,0; 1,2,1]
                half wy = half(dy) * (dx == 0 ? 2.0h : 1.0h);
                gy += luma * wy;
            }
        }
        half edge = clamp(sqrt(gx * gx + gy * gy), 0.0h, 1.0h);
        half4 orig = inTex.read(gid);
        outTex.write(half4(edge, edge, edge, orig.a), gid);
    }

    // MARK: - Sharpen (Unsharp Mask)

    kernel void filter_sharpen(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;

        half4 center = inTex.read(gid);
        half4 neighbors = half4(0);
        int count = 0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                int sx = clamp(int(gid.x) + dx, 0, int(params.width) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(params.height) - 1);
                neighbors += inTex.read(uint2(sx, sy));
                count++;
            }
        }
        neighbors /= half(count);
        half amount = half(params.param1);
        half4 sharpened = center + (center - neighbors) * amount;
        outTex.write(half4(clamp(sharpened.rgb, 0.0h, 1.0h), center.a), gid);
    }

    // MARK: - Sepia

    kernel void filter_sepia(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        half4 c = inTex.read(gid);
        half r = clamp(c.r * 0.393h + c.g * 0.769h + c.b * 0.189h, 0.0h, 1.0h);
        half g = clamp(c.r * 0.349h + c.g * 0.686h + c.b * 0.168h, 0.0h, 1.0h);
        half b = clamp(c.r * 0.272h + c.g * 0.534h + c.b * 0.131h, 0.0h, 1.0h);
        outTex.write(half4(r, g, b, c.a), gid);
    }

    // MARK: - Pixelate

    kernel void filter_pixelate(
        texture2d<half, access::read>  inTex  [[texture(0)]],
        texture2d<half, access::write> outTex [[texture(1)]],
        constant FilterParams &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;
        int blockSize = max(1, int(params.param1));
        uint2 blockOrigin = uint2(
            (gid.x / uint(blockSize)) * uint(blockSize),
            (gid.y / uint(blockSize)) * uint(blockSize)
        );
        half4 c = inTex.read(blockOrigin);
        outTex.write(c, gid);
    }
    """
}
