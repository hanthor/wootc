# Brand configurations

One directory per brand build (docs/branding-and-distribution.md). The binary
embeds every directory; `-ldflags "-X main.brandID=<dir>"` picks which one the
build wears (default `wootc`).

Per-directory files — only `brand.json` is required:

| File | Becomes | Notes |
|---|---|---|
| `brand.json` | `Branding` overlay | identity, palette, catalog, distribution flags |
| `logo.svg` | `LogoDataURI` | the real mark; replaces the emoji everywhere one renders |
| `font.woff2` | `FontDataURI` | the brand's typeface, embedded — never fetched at run time |
| `theme.css` | `ThemeCSS` | deep restyle injected after `style.css` (tokens, buttons, radii) |

## Asset provenance

Real assets, taken from each project's own published branding:

- **bazzite/**: logo `bazzite_b.svg` and the cobalt→violet gradient
  (`#0047ab → #8a2be2`) from [ublue-os/bazzite.gg]; typeface DM Sans
  (site body font; SIL OFL, via Google Fonts).
- **bluefin/**: logo tile (`#3550ec → #252b4b`) from
  [projectbluefin/website] `public/img/logo.svg`; typeface Inter (site
  display font, `--wc-font-display`; SIL OFL).
- **aurora/**: `aurora-logo.svg` and the aurora gradient
  (`#2eb9df → #9e00ff`) from getaurora.dev; typeface Geist (site body
  font; SIL OFL).
- **tunaos/**, **wootc/**: emoji marks — that IS the TunaOS branding today;
  swap in a real `logo.svg` when one exists.

[ublue-os/bazzite.gg]: https://github.com/ublue-os/bazzite.gg
[projectbluefin/website]: https://github.com/projectbluefin/website
