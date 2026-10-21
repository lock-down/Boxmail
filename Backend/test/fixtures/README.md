# Presentation fixtures

These are synthetic Boxmail test documents, with no user mail or attachment data.

The fixtures ship with the local `v0.0.13` source tag and are excluded from the Release app. They were added during the 0.0.9 presentation work and first archived in `v0.0.11`; the current test and release overview is in [the documentation index](../../../docs/README.md).

- `two-slides.pptx`: two Chinese slides containing a deadline, a budget, a three-color embedded image and a column chart. Created with python-pptx.
- `two-slides.ppt`: the same deck exported as PowerPoint 97 by LibreOffice, for legacy format coverage.
- `image-only.pptx`: one slide with the embedded image and no text.
- `hidden-slide.pptx`: the two-slide deck with the second slide hidden.
- `twenty-one-slides.pptx`: the two-slide deck plus 19 numbered slides, to verify the 20-page limit.

Only macOS Quick Look, WebKit and PDFKit are used at runtime. Fixture creation tools are not runtime dependencies. `script/test.sh` builds the bundled native renderer before running the tests; direct `npm test` skips native rendering tests if that component is absent.
