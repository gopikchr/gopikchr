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

### commit dbb1ae84d63db0512aee45c89286aed7580925c4

    Adjust the font size and text length computations for monospace.

    FossilOrigin-Name: 22e2a2c622aa8186d963c5de23e8bc39217b73628affacd5f661e51106156488

 pikchr.c            | 5 +++--
 pikchr.y            | 3 ++-
 tests/test45.pikchr | 2 +-

* Copied the changes over

### commit 39d140c780320f103d19366e4520f175d20812ac

    Remove the artificial enlargement of "mono" text, as that seems not to be
    necessary when the output is rendered by Fossil.  Must be some kind of CSS
    issue.

    FossilOrigin-Name: 03664a38cfb8053340ba733219a2d7ab74d45f10ba32a75f5fb72221238a193f

 pikchr.c | 3 +--
 pikchr.y | 1 -

* Undid 128% extra size for monospaced font

### commit 511e98a82140dcce0174cbe6f98bc24e801f2354

    It seems like the "same" operator should not mess with layout direction.
    See [/forumpost/75a2220c44|forum thread 75a2220c44].

    FossilOrigin-Name: 62b766efe8faea55ef137eeda907c7156a346ced1f620c6ca57c16c9bc45fc84

 pikchr.c             |  4 +---
 pikchr.y             |  2 --
 tests/fonts01.pikchr | 54 ++++++++++++++++++++++++++++++++++++++++++++++++++++
 tests/test77.pikchr  | 11 +++++++++++

* Made the corresponding changes to not override direction
