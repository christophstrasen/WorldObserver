@TODO

Please review all of our busted unit tests to see if any of those are pretty much useless because they may test something with a very low chance to break or because they simply test stubs or shims that don't reflect the real code-base any more.
Also try to analyze if there are cross-cutting concerns that either could use an addtional test or where merging tests can make them more powerful.

Highlight for derived streams that joining 1:1 (one square one zombie) by ID fields is useful but that joins can also do broad things, like categories where multiple different squares match the zombie because the dimension is not spatial


Quick detour to the the family of spriteObservations. The  record shows it contains (at runtime possibly already "dead") references to IsoSquare and IsoObject _if_ we collect them.
I believe we should:
1. Always collect them and not make it optional (they are just references). That should remove knobs and make shape more predictable
2. Re-use the existing hydration we have for IsoSquares (chack the related helpers e.g. `hydrateIsoGridSquare` and how it is being used). And if re-using that hydration wuld benefit from a light refactor then I am all ears for options
3. We cannot do  good hydration for the object because there is no good id