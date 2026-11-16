# Reader annotation limitations

On a tested Android device, Readium Kotlin 3.2.0 selections expose empty
`locations.fragments` and `otherLocations`. The selection contract provides no
ordered start/end boundaries, and Readium exposes no supported API to resolve
text for an arbitrary merged locator.

Therefore overlap detection and annotation union merging are deferred. Exact
duplicate protection remains limited to `(bookId, locationKey)`. Visually
overlapping annotations can coexist; no user data is automatically deleted,
merged, or rewritten.

Revisit this only after a Readium upgrade or supported range-selector API
provides ordered boundaries, stable range serialization, exact merged-text
resolution, atomic repository merge behavior, and a legacy-data policy.
