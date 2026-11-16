# License scope

## Project license

The original BiblioLife application code and other contributions authored for BiblioLife, to the extent the relevant contributors hold the necessary rights to license them, are licensed under **GNU General Public License version 3 or (at your option) any later version (GPL-3.0-or-later)**. See the complete license text in [`LICENSE`](LICENSE).

This is a license grant for covered original BiblioLife material. It is not a transfer of copyright ownership and does not assert that BiblioLife owns third-party material.

## Material not automatically covered by the root license

The root license does not override a separate license or permission applying to third-party or independently licensed material. This includes, where applicable:

- vendored projects and source trees under `third_party/`;
- Readium Kotlin Toolkit and its separately licensed upstream components;
- fonts, icon artwork, illustrations, images and other media obtained from external sources;
- Flutter, Android, Gradle, Maven, npm and other dependencies;
- generated assets copied from SDK or framework templates;
- test fixtures, sample publications, books, covers, and other reference content;
- any file carrying its own copyright, license, attribution, or redistribution notice.

For these materials, retain the applicable upstream license and notices. Consult [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the relevant license files. A mention in the notices is not by itself proof that every binary or asset has been cleared for redistribution.

## Excluded material

The legacy Nimbus Android Fonts Patch WOFF files have been removed from this candidate and are excluded from future CSS asset-copy builds because their exact redistribution grant was not established. This does not relicense or resolve the rights to those fonts; they are simply not redistributed here. The app does not currently load the optional patch. Fixed-Layout EPUBs relying on unembedded Times/Arial-compatible font metrics may therefore use Android system fallback metrics; see `docs/release/android-fxl-font-patch.md`. The 147-item historical resource inventory reviewed for this candidate has been resolved through upstream attribution, licensed replacement, owner-confirmed artwork, project-owned fixtures or exclusion; see `docs/release/asset-provenance.md`. New resources added later still require provenance and license review. BiblioLife v1.0.0 excludes Junrar and CBR/RAR extraction.

## Contributions

Contributors may submit only material they have the right to license under GPL-3.0-or-later or clearly identified third-party material whose separate terms permit the intended use. Do not submit copied assets or code without recording the source and applicable license.
