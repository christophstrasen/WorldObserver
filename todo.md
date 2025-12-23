@TODO

Please review all of our busted unit tests to see if any of those are pretty much useless because they may test something with a very low chance to break or because they simply test stubs or shims that don't reflect the real code-base any more.
Also try to analyze if there are cross-cutting concerns that either could use an addtional test or where merging tests can make them more powerful.

Highlight for derived streams that joining 1:1 (one square one zombie) by ID fields is useful but that joins can also do broad things, like categories where multiple different squares match the zombie because the dimension is not spatial


About something else. The family of spriteObservations. Its record.lua shows it contains (at runtime possibly already "dead") references to IsoSquare and IsoObject _if_ we collect them.
```		if opts.includeIsoObject then
			record.IsoObject = isoObject
		end
		if opts.includeIsoSquare and square ~= nil then
			record.IsoSquare = square
		end``` 
I believe we should:
1. Always collect them and not make it optional (they are just references). That should remove code complexity, knobs and make shape more predictable
2. Re-use the existing hydration we have for IsoSquares (check the related helpers e.g. `hydrateIsoGridSquare` and how it is being used). And if re-using that hydration would benefit from a light refactor then I am all ears for options
3. We cannot do good hydration for the object because there is no good id


Please add a new user-facing stream-helper for the sprite family. we should call it `removeAssociatedTileObject` and it takes no parameter (it implies the object whichs sprite we observed). Internally it uses the zomboid function `IsoGridSquare:RemoveTileObject(IsoObject obj)` which will remove the object handed to it (onnly works for tile objects, not workd objects). 
Now, as the stream helper  is supposed to work on sprite observations, we have to get the IsoGridSquare that is associated with that sprite _and_  the object the sprite observation belongs to. We do have IsoSquare and IsoObject available at the  sprite record now. Even though only one of them has a hydration we cannot guarantee they will exist anyway.