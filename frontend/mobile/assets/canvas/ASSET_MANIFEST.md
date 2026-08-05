# Canvas asset manifest

All assets are for internal Dodam project usage. The grayscale source icons are the geometry authority; robust bounds ignore isolated alpha noise below 16/255. Each authority silhouette is aspect-preservingly contained and centered in the 224px safe box. Border-connected chroma is removed from each fixed color reference, the reference is aspect-preservingly contained, and then the reviewed reference-only affine below is applied around the contain center. Raw registered reference alpha must cover at least 98% of authority alpha before authority alpha is imposed. Gate masks are binarized at alpha>=16 before registration and transformed with nearest-neighbor sampling; Lanczos resampling is used only for visual RGBA and cannot add gate support. No dilation, blur, or support expansion participates in this gate.

Transform order: alpha>=16 binary masks -> authority bbox contain -> reference bbox contain -> reference-only scaleX/scaleY -> reference-only translateX/translateY -> nearest-neighbor raw binary alpha intersection gate -> authority alpha output. Translation values are output-canvas pixels. The palette metadata is contract-tested as the first passing four-decimal uniform-scale breakpoint after exhaustively checking every valid integer translation at each smaller breakpoint.

| Tool | scaleX | scaleY | translateX | translateY | Registered raw overlap |
| --- | ---: | ---: | ---: | ---: | ---: |
| brush | 1.0000 | 1.0000 | 0.00 | 0.00 | 98.89% |
| crayon | 1.0000 | 1.0000 | 0.00 | 0.00 | 98.99% |
| eraser | 1.1000 | 1.1000 | 1.00 | 2.00 | 98.12% |
| fill | 1.0427 | 1.0427 | -3.00 | -1.00 | 98.08% |
| palette | 1.0067 | 1.0067 | 0.00 | 4.00 | 98.06% |
| pencil | 1.0125 | 1.0125 | -1.00 | 0.00 | 98.31% |

The verified handoff point masks use the registered 224px safe-box coordinate system. They follow the authority's explicit contain affine, then are clipped to the authoritative output alpha.

| Runtime asset | Source | Dimensions | Mask role | Usage |
| --- | --- | --- | --- | --- |
| tools/brush_base.png | tools/brush.png + color-references/brush.png | 256x256 | tools/masks/brush_point.png | Canvas toolbar |
| tools/crayon_base.png | tools/crayon.png + color-references/crayon.png | 256x256 | tools/masks/crayon_point.png | Canvas toolbar |
| tools/eraser_base.png | tools/eraser.png + color-references/eraser.png | 256x256 | none | Canvas toolbar |
| tools/fill_base.png | tools/fill.png + color-references/fill.png | 256x256 | tools/masks/fill_point.png | Canvas toolbar |
| tools/palette_base.png | tools/palette.png + color-references/palette.png | 256x256 | none | Canvas toolbar |
| tools/pencil_base.png | tools/pencil.png + color-references/pencil.png | 256x256 | tools/masks/pencil_point.png | Canvas toolbar |
| tools/masks/brush_point.png | masks/brush-point.png | 256x256 | Registered variable-region alpha, clipped to artwork | Canvas tool color region |
| tools/masks/crayon_point.png | masks/crayon-point.png | 256x256 | Registered variable-region alpha, clipped to artwork | Canvas tool color region |
| tools/masks/fill_point.png | masks/fill-point.png | 256x256 | Registered variable-region alpha, clipped to artwork | Canvas tool color region |
| tools/masks/pencil_point.png | masks/pencil-point.png | 256x256 | Registered variable-region alpha, clipped to artwork | Canvas tool color region |
| swatches/red.png | swatches/red.png | 48x48 | none | Canvas color picker |
| swatches/orange.png | swatches/orange.png | 48x48 | none | Canvas color picker |
| swatches/yellow.png | swatches/yellow.png | 48x48 | none | Canvas color picker |
| swatches/green.png | swatches/green.png | 48x48 | none | Canvas color picker |
| swatches/teal.png | swatches/teal.png | 48x48 | none | Canvas color picker |
| swatches/blue.png | swatches/blue.png | 48x48 | none | Canvas color picker |
| swatches/purple.png | swatches/purple.png | 48x48 | none | Canvas color picker |
| swatches/charcoal.png | swatches/charcoal.png | 48x48 | none | Canvas color picker |
| frame/back.png | frame/back.png | source dimensions | none | Canvas chrome |
| frame/undo.png | frame/undo.png | source dimensions | none | Canvas chrome |
| frame/redo.png | frame/redo.png | source dimensions | none | Canvas chrome |
| frame/save.png | frame/save.png | source dimensions | none | Canvas chrome |
| frame/button_green.png | frame/button_green.png | source dimensions | none | Canvas chrome |
| frame/button_yellow.png | frame/button_yellow.png | source dimensions | none | Canvas chrome |
| frame/canvas_frame_mobile.png | frame/canvas_frame_mobile.png | source dimensions | none | Canvas chrome |
| frame/canvas_frame_tablet.png | frame/canvas_frame_tablet.png | source dimensions | none | Canvas chrome |
| frame/toolbar_frame_mobile.png | frame/toolbar_frame_mobile.png | source dimensions | none | Canvas chrome |
| frame/toolbar_frame_tablet.png | frame/toolbar_frame_tablet.png | source dimensions | none | Canvas chrome |
| frame/frame_patch_graphite.png | frame/frame_patch_graphite.png | source dimensions | none | Canvas chrome |
| frame/paper_texture.png | frame/paper_texture.png | source dimensions | none | Canvas chrome |
| frame/selected_tool.png | frame/selected_tool.png | source dimensions | none | Canvas chrome |
| frame/slider_track.png | frame/slider_track.png | source dimensions | none | Canvas chrome |
| frame/speech_bubble.png | frame/speech_bubble.png | source dimensions | none | Canvas chrome |
| frame/spiral_mobile.png | frame/spiral_mobile.png | source dimensions | none | Canvas chrome |
| frame/spiral_tablet.png | frame/spiral_tablet.png | source dimensions | none | Canvas chrome |

The removed yellow outer-frame patch is intentionally absent.
