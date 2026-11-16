# Contributing

BiblioLife is under active development. Follow the [README](README.md) and [setup guide](docs/development/setup.md) to install Flutter, Dart, Android SDK and the required Java tooling. Run `flutter pub get --enforce-lockfile` before working, and keep local settings and secrets out of changes.

Use the existing Dart formatting and analysis conventions (`dart format` and `flutter analyze --no-pub`). Keep changes focused, explain their purpose, and include relevant tests. Run the affected tests and disclose failures or tests you could not run; the existing full suite has known failures. For Reader changes also check the applicable Android, Readium and JavaScript tests described in the README and development documentation.

For a pull request, describe the behavior, rationale, validation, and limitations. Preserve third-party notices and identify the origin and license of newly added dependencies or assets. Do not include private books, device captures, credentials or local configuration.

Submit only material you have the right to contribute. Original BiblioLife code and project-owned contributions are distributed under GPL-3.0-or-later; by submitting a contribution, you agree that your contribution may be distributed under those terms, unless a different arrangement is agreed in writing. Preserve any separate applicable third-party terms and clearly identify them. Do not assert ownership on behalf of others. Do not contribute fonts, icons, images, test publications, or other assets unless you can identify their source and redistribution license.
