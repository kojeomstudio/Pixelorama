# AGENTS.md

Pixelorama is an open-source 2D pixel art editor built entirely in GDScript on **Godot 4.6.1** (no C#/Mono required). Main scene: `res://src/Main.tscn`. Current file format versions are tracked in `project.godot`: `config/ExtensionsAPI_Version` (8) and `config/Pxo_Version` (6).

## Layout

- `src/Autoload/` — singleton autoloads registered in `project.godot` (`Global`, `Tools`, `DrawingAlgos`, `OpenSave`, `Export`, `Import`, `Palettes`, `Themes`, `ExtensionsApi`, ...). Access them anywhere as `Global.foo` etc.; `Global.gd` is the central hub.
- `src/Classes/` — core data model: `Project`, `Frame`, `Layers/`, `Cels/`, `ImageExtended`, `AnimationTag`, `SelectionMap`, `SoftwareParsers/`.
- `src/Tools/` — drawing tools. All inherit from `BaseTool`/`BaseDraw`/`BaseSelectionTool` (subdirs: `3DTools`, `DesignTools`, `SelectionTools`, `UtilityTools`).
- `src/UI/` — interface scenes/scripts (`Dialogs/`, `Timeline/`, `Canvas/`, `ToolsPanel/`, ...).
- `src/Shaders/`, `src/Palette/`, `src/Preferences/` — effects, palette UI, preferences.
- `addons/` — vendored plugins (`keychain` shortcuts, `dockable_container` UI, `gdgifexporter`, ...). Avoid editing; CI watches this path.
- `assets/` — graphics/other assets. `pixelorama_data/` — default brushes, palettes, patterns.
- `Translations/` — `Translations.pot` (template) plus `*.po` files managed by Crowdin.
- `Misc/` — Linux desktop/packaging files.

## Commands

There is no test suite. Verification is formatting, linting, and running the app.

- Run: open `project.godot` in the Godot 4.6.1 editor or `godot -e` / `godot` from the repo root. Older Godot versions will not work.
- Format (CI enforced): `gdformat --diff .` from the repo root (auto-fix: `gdformat .`).
- Lint (CI enforced): `gdlint .` — config in `.gdlintrc` (relaxed return/line rules).
- Headless re-import after adding assets: `godot --headless -v --import`.
- Exports are defined in `export_presets.cfg`; CI (`.github/workflows/`) exports via `godot --headless --export-release "<preset name>"` using the `barichello/godot-ci` image.

## Conventions (from CONTRIBUTING.md)

- Follow the GDScript style guide; **static typing is required**. Trim trailing whitespace; files end with a single blank line. Remove unused template comments/methods Godot inserts into new scripts.
- New scripts/scenes go in `src/` with `PascalCase` names; new assets go in `assets/` with `snake_case` names.
- Godot churns scene files by itself — do not include scene changes (especially `Main.tscn`) in commits unless intentionally edited.
- Edit `PackedScene` UI elements in their own scene files, never in `Main.tscn` or parent scenes. New popup/dialog scenes must start with visibility off.
- New user-facing strings go into `Translations.pot` only (never the `*.po` files — Crowdin owns those). Group related strings/tooltip pairs together.
- Buttons and other interactive UI elements must set the pointing-arrow mouse cursor; add hint tooltips (also in `Translations.pot`).
- Reuse the existing `ErrorDialog` for errors instead of creating new ones.

## Gotchas

- Do not base work on or open PRs targeting `l10n_master`, `release`, or `gh-pages`.
- Every script has a sibling `.gd.uid` file; keep them together when moving files.
- `src/Autoload/ExtensionsApi.gd` is the public extension API for third-party extensions — treat its surface as a compatibility contract; the API version lives in `project.godot`.
- The web (HTML5) build is a first-class target: guard platform-specific code (see the `Html5FileExchange` autoload) and don't assume desktop-only features.
- One topic per PR/commit; rebase onto `master` before submitting.
