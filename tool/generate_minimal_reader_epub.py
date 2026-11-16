"""Generates the deterministic Readium smoke-test EPUB fixture."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

OUT = Path(__file__).parents[1] / "test" / "fixtures" / "minimal_reader.epub"
FILES = [
    ("mimetype", "application/epub+zip", ZIP_STORED),
    ("META-INF/container.xml", '''<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''', ZIP_DEFLATED),
    ("OEBPS/package.opf", '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="en"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:uuid:bibliolife-readium-test-book</dc:identifier><dc:title>BiblioLife Readium Test Book</dc:title><dc:creator>BiblioLife Test Suite</dc:creator><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/><item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/><item id="css" href="styles.css" media-type="text/css"/></manifest><spine><itemref idref="chapter1"/><itemref idref="chapter2"/></spine></package>''', ZIP_DEFLATED),
    ("OEBPS/nav.xhtml", '''<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en"><head><title>Navigation</title></head><body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">First Test Chapter</a></li><li><a href="chapter2.xhtml">Second Test Chapter</a></li></ol></nav></body></html>''', ZIP_DEFLATED),
    ("OEBPS/chapter1.xhtml", '''<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" lang="en"><head><title>First Test Chapter</title><link rel="stylesheet" type="text/css" href="styles.css"/></head><body><h1>First Test Chapter</h1><p>BiblioLife opened the first test chapter successfully.</p><p>This original fixture gives the navigator enough content for a deterministic smoke test.</p><p>The next chapter carries a different opening sentence for restoration verification.</p></body></html>''', ZIP_DEFLATED),
    ("OEBPS/chapter2.xhtml", '''<?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" lang="en"><head><title>Second Test Chapter</title><link rel="stylesheet" type="text/css" href="styles.css"/></head><body><h1>Second Test Chapter</h1><p>BiblioLife restored the second test chapter successfully.</p><p>This is original project-owned text, designed to be visibly distinct from chapter one.</p><p>Closing here provides a stable locator for the next reader launch.</p></body></html>''', ZIP_DEFLATED),
    ("OEBPS/styles.css", "body { font-family: sans-serif; line-height: 1.5; }", ZIP_DEFLATED),
]

def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUT, "w") as z:
        for name, content, compression in FILES:
            info = ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = compression
            z.writestr(info, content.encode("utf-8"))
    print(OUT)

if __name__ == "__main__":
    main()
