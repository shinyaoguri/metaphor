#!/usr/bin/env python3
"""Generate the metaphor ribbon as an editable procedural 3D mesh."""

from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent

# Five cubic segments traced from the selected upper-left logo concept.
CURVE = np.array(
    [
        [[112, 370], [108, 250], [200, 150], [235, 214]],
        [[235, 214], [257, 254], [245, 350], [273, 358]],
        [[273, 358], [315, 370], [325, 252], [366, 252]],
        [[366, 252], [407, 252], [380, 366], [409, 374]],
        [[409, 374], [440, 382], [450, 340], [480, 350]],
    ],
    dtype=np.float64,
)

MATERIALS = {
    "ivory": np.array([0xF4, 0xED, 0xE4], dtype=np.float64),
    "silver": np.array([0xC8, 0xC9, 0xCF], dtype=np.float64),
    "edge": np.array([0xDD, 0xD9, 0xD2], dtype=np.float64),
}


def bezier(points: np.ndarray, t: np.ndarray) -> np.ndarray:
    one = 1.0 - t
    return (
        one[:, None] ** 3 * points[0]
        + 3 * one[:, None] ** 2 * t[:, None] * points[1]
        + 3 * one[:, None] * t[:, None] ** 2 * points[2]
        + t[:, None] ** 3 * points[3]
    )


def centerline(samples: int) -> np.ndarray:
    dense_parts = []
    for segment_index, segment in enumerate(CURVE):
        values = np.linspace(0.0, 1.0, 120, endpoint=segment_index == len(CURVE) - 1)
        dense_parts.append(bezier(segment, values))
    dense = np.concatenate(dense_parts)
    distances = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))]
    targets = np.linspace(0.0, distances[-1], samples)
    x = np.interp(targets, distances, dense[:, 0])
    y = np.interp(targets, distances, dense[:, 1])

    # Normalize the traced coordinates into convenient model units.
    result = np.column_stack(((x - 300.0) / 100.0, (310.0 - y) / 100.0, np.zeros_like(x)))
    return result


def capsule_section(half_width: float, half_thickness: float, arc_steps: int = 5) -> np.ndarray:
    radius = half_thickness
    left_center = -half_width + radius
    right_center = half_width - radius
    # Half-open ranges avoid duplicate vertices where the semicircles meet.
    left_angles = np.linspace(math.pi / 2, 3 * math.pi / 2, arc_steps, endpoint=False)
    right_angles = np.linspace(3 * math.pi / 2, 5 * math.pi / 2, arc_steps, endpoint=False)
    left = np.column_stack((left_center + radius * np.cos(left_angles), radius * np.sin(left_angles)))
    right = np.column_stack((right_center + radius * np.cos(right_angles), radius * np.sin(right_angles)))
    return np.vstack((left, right))


def build_mesh(samples: int = 260, twist_turns: float = 1.0):
    core = centerline(samples)
    core_progress = np.linspace(0.0, 1.0, samples)
    core_tangents = np.gradient(core, axis=0)
    core_tangents /= np.linalg.norm(core_tangents, axis=1, keepdims=True)

    # Extend the centerline by one half-width at each end. The section width
    # follows a semicircle, producing the rounded terminals visible in the
    # reference instead of a flat cut.
    cap_steps = 18
    start_width = 0.40
    end_width = 0.40 * (1.0 - 0.34)
    start_distances = np.linspace(start_width, start_width / cap_steps, cap_steps)
    end_distances = np.linspace(end_width / cap_steps, end_width, cap_steps)
    start_cap = core[0] - start_distances[:, None] * core_tangents[0]
    end_cap = core[-1] + end_distances[:, None] * core_tangents[-1]
    start_widths = np.sqrt(np.maximum(0.0, start_width**2 - start_distances**2))
    end_widths = np.sqrt(np.maximum(0.0, end_width**2 - end_distances**2))

    centers = np.vstack((start_cap, core, end_cap))
    progress = np.r_[np.zeros(cap_steps), core_progress, np.ones(cap_steps)]
    widths = np.r_[start_widths, 0.40 * (1.0 - 0.34 * core_progress), end_widths]
    tangents = np.gradient(centers, axis=0)
    tangents /= np.linalg.norm(tangents, axis=1, keepdims=True)

    vertices = []
    sections = []
    cross_count = 10
    for index, (point, tangent, s, width) in enumerate(zip(centers, tangents, progress, widths)):
        planar_normal = np.array([-tangent[1], tangent[0], 0.0])
        planar_normal /= np.linalg.norm(planar_normal)
        binormal = np.array([0.0, 0.0, 1.0])

        # Two half-turns expose ivory, silver, then ivory again from the front.
        angle = twist_turns * 2.0 * math.pi * s
        width_axis = math.cos(angle) * planar_normal + math.sin(angle) * binormal
        thickness_axis = np.cross(tangent, width_axis)
        thickness_axis /= np.linalg.norm(thickness_axis)

        half_thickness = 0.045 * (1.0 - 0.18 * s)
        half_width = max(float(width), half_thickness)
        section = capsule_section(half_width, half_thickness)
        assert len(section) == cross_count
        ring = point + section[:, 0, None] * width_axis + section[:, 1, None] * thickness_axis
        sections.append(section)
        vertices.extend(ring)

    vertices = np.asarray(vertices, dtype=np.float64)
    faces = []
    face_materials = []
    ring_count = len(centers)
    for ring in range(ring_count - 1):
        section = sections[ring]
        for edge in range(cross_count):
            next_edge = (edge + 1) % cross_count
            a = ring * cross_count + edge
            b = (ring + 1) * cross_count + edge
            c = (ring + 1) * cross_count + next_edge
            d = ring * cross_count + next_edge
            midpoint_v = (section[edge, 1] + section[next_edge, 1]) / 2.0
            if midpoint_v > section[:, 1].max() * 0.7:
                material = "ivory"
            elif midpoint_v < section[:, 1].min() * 0.7:
                material = "silver"
            else:
                material = "edge"
            faces.extend(((a, b, c), (a, c, d)))
            face_materials.extend((material, material))

    # Close both rounded ends with triangle fans.
    for ring, reverse in ((0, True), (ring_count - 1, False)):
        center_index = len(vertices)
        vertices = np.vstack((vertices, vertices[ring * cross_count : (ring + 1) * cross_count].mean(axis=0)))
        for edge in range(cross_count):
            next_edge = (edge + 1) % cross_count
            pair = (ring * cross_count + edge, ring * cross_count + next_edge)
            faces.append((center_index, pair[1], pair[0]) if reverse else (center_index, pair[0], pair[1]))
            face_materials.append("edge")

    return vertices, np.asarray(faces, dtype=np.int32), face_materials


def write_obj(vertices: np.ndarray, faces: np.ndarray, materials: list[str]) -> None:
    obj_path = ROOT / "metaphor-ribbon.obj"
    mtl_path = ROOT / "metaphor-ribbon.mtl"
    with mtl_path.open("w", encoding="utf-8") as stream:
        for name, color in MATERIALS.items():
            rgb = color / 255.0
            stream.write(f"newmtl {name}\nKd {rgb[0]:.6f} {rgb[1]:.6f} {rgb[2]:.6f}\n")
            stream.write("Ka 0.080000 0.080000 0.080000\nKs 0.160000 0.160000 0.160000\nNs 48\nillum 2\n\n")

    grouped = {name: [] for name in MATERIALS}
    for face, material in zip(faces, materials):
        grouped[material].append(face)

    with obj_path.open("w", encoding="utf-8") as stream:
        stream.write("# Procedural metaphor ribbon\nmtllib metaphor-ribbon.mtl\no metaphor_ribbon\n")
        for vertex in vertices:
            stream.write(f"v {vertex[0]:.8f} {vertex[1]:.8f} {vertex[2]:.8f}\n")
        for material, material_faces in grouped.items():
            stream.write(f"usemtl {material}\n")
            for face in material_faces:
                stream.write(f"f {face[0] + 1} {face[1] + 1} {face[2] + 1}\n")


def write_binary_stl(vertices: np.ndarray, faces: np.ndarray) -> None:
    path = ROOT / "metaphor-ribbon.stl"
    with path.open("wb") as stream:
        stream.write(b"metaphor ribbon".ljust(80, b"\0"))
        stream.write(struct.pack("<I", len(faces)))
        for face in faces:
            triangle = vertices[face]
            normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
            length = np.linalg.norm(normal)
            normal = normal / length if length else normal
            stream.write(struct.pack("<12fH", *(normal.tolist() + triangle.reshape(-1).tolist()), 0))


def rotation_matrix(yaw: float, pitch: float, roll: float) -> np.ndarray:
    y, p, r = np.radians([yaw, pitch, roll])
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    return rz @ rx @ ry


def render_preview(
    vertices: np.ndarray,
    faces: np.ndarray,
    materials: list[str],
    yaw: float,
    pitch: float,
    roll: float,
    size: int = 900,
) -> None:
    rotation = rotation_matrix(yaw, pitch, roll)
    transformed = vertices @ rotation.T
    xy = transformed[:, :2]
    minimum = xy.min(axis=0)
    maximum = xy.max(axis=0)
    extent = maximum - minimum
    scale = (size * 0.76) / max(extent)
    projected = np.empty_like(xy)
    projected[:, 0] = (xy[:, 0] - (minimum[0] + maximum[0]) / 2.0) * scale + size / 2.0
    projected[:, 1] = size / 2.0 - (xy[:, 1] - (minimum[1] + maximum[1]) / 2.0) * scale
    depth = transformed[:, 2]

    background = np.array([0x07, 0x14, 0x26], dtype=np.uint8)
    image = np.broadcast_to(background, (size, size, 3)).copy()
    zbuffer = np.full((size, size), -np.inf, dtype=np.float64)
    light = np.array([-0.35, 0.55, 0.76])
    light /= np.linalg.norm(light)

    for face, material in zip(faces, materials):
        points = projected[face]
        z = depth[face]
        x0 = max(0, int(math.floor(points[:, 0].min())))
        x1 = min(size - 1, int(math.ceil(points[:, 0].max())))
        y0 = max(0, int(math.floor(points[:, 1].min())))
        y1 = min(size - 1, int(math.ceil(points[:, 1].max())))
        if x1 < x0 or y1 < y0:
            continue

        a, b, c = points
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-10:
            continue
        grid_x, grid_y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((b[1] - c[1]) * (grid_x - c[0]) + (c[0] - b[0]) * (grid_y - c[1])) / denominator
        w1 = ((c[1] - a[1]) * (grid_x - c[0]) + (a[0] - c[0]) * (grid_y - c[1])) / denominator
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        interpolated_depth = w0 * z[0] + w1 * z[1] + w2 * z[2]
        target = zbuffer[y0 : y1 + 1, x0 : x1 + 1]
        visible = inside & (interpolated_depth > target)
        if not visible.any():
            continue

        triangle = transformed[face]
        normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
        normal_length = np.linalg.norm(normal)
        if normal_length:
            normal /= normal_length
        diffuse = max(0.0, float(np.dot(normal, light)))
        intensity = 0.87 + 0.13 * diffuse
        color = np.clip(MATERIALS[material] * intensity, 0, 255).astype(np.uint8)
        target[visible] = interpolated_depth[visible]
        image[y0 : y1 + 1, x0 : x1 + 1][visible] = color

    Image.fromarray(image).resize((768, 768), Image.Resampling.LANCZOS).save(ROOT / "metaphor-ribbon-preview.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yaw", type=float, default=-11.0)
    parser.add_argument("--pitch", type=float, default=7.0)
    parser.add_argument("--roll", type=float, default=0.0)
    parser.add_argument("--twist-turns", type=float, default=1.0)
    args = parser.parse_args()

    vertices, faces, materials = build_mesh(twist_turns=args.twist_turns)
    write_obj(vertices, faces, materials)
    write_binary_stl(vertices, faces)
    render_preview(vertices, faces, materials, args.yaw, args.pitch, args.roll)
    print(f"vertices={len(vertices)} triangles={len(faces)}")


if __name__ == "__main__":
    main()
