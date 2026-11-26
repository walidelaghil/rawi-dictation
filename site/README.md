# Rawi landing site

Plain static HTML, CSS and JS. No build step.

| File | Role |
|---|---|
| `index.html` | Markup |
| `styles.css` | Styles |
| `engine.js` | The demo's cleanup engine (tested) |
| `copy.js` | All Arabic and English copy, plus demo data |
| `app.js` | UI: demo, tabs, pre-sale pop-up, language toggle |
| `_headers` | Cloudflare Pages headers. Grants the microphone to the page, which the hero demo needs |

## Run locally

```bash
python3 -m http.server 8787 --directory site
```

Open http://localhost:8787/. Run the engine tests with `node --test site/test/`.

## Deploy to rawi.waleedelaghil.com (Cloudflare Pages, like Salasa)

1. Cloudflare dashboard, Workers & Pages, Create, Pages, connect `walidelaghil/rawi-dictation`.
2. Framework preset: None. Build command: empty. Build output directory: `site`.
3. After the first deploy, Custom domains, add `rawi.waleedelaghil.com`. Cloudflare creates the CNAME to the `*.pages.dev` host, since `waleedelaghil.com` is already on Cloudflare.
4. Open the live URL and hold the mic button once to confirm the browser asks for microphone permission.

## Still open

- The "Reserve my copy for $29" button is inert. Put the checkout link in `app.js`: search for `href="#buy"` and replace it, then remove `aria-disabled` and the `#buy` branch of the click handler.
- Build and maintenance hours in the pop-up calculator (`BUILD=90, MAINT=30` in `app.js`) are estimates. Replace them with real numbers.
- The Vibe button opens `https://github.com/walidelaghil/rawi-dictation` in a new tab.
