// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors
//
// Resolves a wordmark out of noise, as a signal surfacing from deep
// water. Built to .qsb at install time (lib/install/config_deploy.sh);
// components/SignalText.qml falls back to plain text if that build never
// ran.
//
// Every colour arrives as a uniform from the live palette. Nothing here
// picks a hue.
//
// The mark is never allowed to resolve into solid ink. At rest the
// interior stays dim and the emission lives in the edge, so the letters
// read as something lit from within rather than as printed text -- the
// first version drove the interior to full strength at progress 1 and
// looked exactly like a white label on black, which is the one outcome
// this shader exists to avoid.

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    float aspect;
    vec4 inkColour;
    vec4 glowColour;
    float grain;
    float bloom;
};

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float unresolved = 1.0 - progress;

    // Fragmented displacement: the mark arrives in horizontal strata that
    // slide independently. The exponent is low enough that the strata are
    // still perceptibly loose at rest -- a signal that has locked
    // perfectly is a logo, not a signal.
    float bands = mix(11.0, 38.0, progress);
    float band = floor(uv.y * bands);
    float bandSeed = hash(vec2(band, floor(time * 0.7)));
    float slide = (bandSeed - 0.5) * 0.13 * pow(unresolved + 0.16, 1.35);

    // One travelling refraction lens rather than a per-frame jitter. It
    // keeps sweeping after the mark resolves, which is most of what makes
    // the surface read as alive rather than paused.
    float sweep = fract(time * 0.075);
    float lens = exp(-pow((uv.y - sweep) * 11.0, 2.0));
    float refracted = lens * 0.03 * (0.5 + 0.5 * unresolved);

    vec2 warped = vec2(uv.x + slide + refracted, uv.y);
    warped.y += unresolved * 0.014;

    float mark = texture(source, warped).a;

    // Etching. `bite` never reaches zero, so the letterforms keep a live
    // grain instead of hardening into flat shapes once resolved.
    vec2 grainUv = vec2(uv.x * aspect, uv.y) * 210.0;
    float etch = noise(grainUv + vec2(0.0, time * 0.32));
    float fine = hash(floor(grainUv * 1.7) + floor(time * 6.0));
    // The window matters more than the constants. smoothstep(0.0, 0.62, ..)
    // saturated at 1 for every progress above about 0.4, so the etching
    // vanished the moment the mark resolved and the breathing did nothing
    // -- measured at 0.2% of pixels changing across a whole breath. This
    // window keeps the gate inside its own ramp for the range the mark
    // actually lives in.
    float bite = 0.14 + 0.86 * unresolved;
    float gate = smoothstep(0.30, 0.90, progress * 1.12 - (etch * 0.55 + fine * grain * 0.45) * bite);

    float body = mark * gate;

    // Edge emission. The difference between the mark and an eroded copy
    // approximates the outline without a second pass, and that outline
    // carries almost all of the light.
    float e = 0.0038;
    float erode = texture(source, warped + vec2(e, 0.0)).a
                * texture(source, warped - vec2(e, 0.0)).a
                * texture(source, warped + vec2(0.0, e * aspect)).a
                * texture(source, warped - vec2(0.0, e * aspect)).a;
    float edge = clamp(mark - erode, 0.0, 1.0) * gate;

    // Dim, and deliberately capped well below solid. Depth comes from the
    // interior being darker than its own outline.
    float interior = body * mix(0.08, 0.42, smoothstep(0.25, 1.0, progress));

    vec3 rgb = inkColour.rgb * interior
             + glowColour.rgb * edge * (1.15 + bloom * 1.1)
             + glowColour.rgb * body * lens * 0.45;

    float alpha = clamp(interior * 1.5 + edge * (1.25 + bloom * 0.7), 0.0, 1.0);
    fragColor = vec4(rgb, 1.0) * alpha * qt_Opacity;
}
