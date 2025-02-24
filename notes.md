# Notes

## Changes

### commit b3e5f5a460815634be1eaf87eaaa80607126b8a9

    Add the narrow.pikchr test case.  This should have been part of
    [21ca6b843d65c404], I think.

    FossilOrigin-Name: 2fa0a525f8f246b78ee620cdc4441851c72bb98f986062fb0d88a7a1a61e3516

 tests/narrow.pikchr | 20 ++++++++++++++++++++

* copied `tests/narrow.pikchr over`

### commit 8b37a92883ceefd0588dceaeb8b65f065c2300a6

    Experimental support for the "mono" and "monospace" text attributes.

    FossilOrigin-Name: 0204bf918707fc793d0e4441c0fd954e471833db838e20cbdd980afb69202c82

 doc/differences.md         |    2 +-
 doc/grammar.md             |    2 +
 doc/textattr.md            |   11 +
 doc/userman.md             |   11 +
 fuzzcases/monospace.pikchr |    1 +
 pikchr.c                   | 1862 ++++++++++++++++++++++----------------------
 pikchr.y                   |   47 +-
 tests/test40.pikchr        |    2 +-
 tests/test45.pikchr        |    3 +-

* Copied code over; updated tests

### commit 90342052ad7ae93f49f6eae66efece1dac498501

    "mono italic" test case added.

    FossilOrigin-Name: fc34d765e110d2b1dba6d7037455494a46a6e2ae4a39fe5d4056217c82ce369b

 tests/test45.pikchr | 2 +-

* only a test was updated; easy!
