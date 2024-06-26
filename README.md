Create rain overlay on your mac!
![](https://github.com/futuun/dszcz/assets/15254260/da70a993-9cb6-4c1d-91a4-887488cf4d3d)

### How does it work?

[Overlay window](./dszcz/OverlayWindow.swift) is rendered on the main screen and always moves to active space. Everything is covered, but mouse events are not being captured.
<br>
[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) allows streaming desktop content, and since it captures frames before composition, anything can be excluded from the output ([in our case overlay window is ommited](./dszcz/CaptureEngine.swift#L18-L21)). Frames are saved into [Metal texture](./dszcz/MetalRenderer.swift#L118-L120) in near real time and since it's rendered in the overlay that is ignoring mouse events, user can freerly interact with system underneath.
<br>
Since overlay is [MTKView](https://developer.apple.com/documentation/metalkit/mtkview/) it can be freerly manipulate before being shown to the user (in our case [rain texture](./dszcz/MetalRenderer.swift#L197-L198) is used to render ripples and distort the [screen feed](./dszcz/Shaders.metal#L37-L39).

Rain effect itself is really old trick, this is [pretty good explanation how it works](https://web.archive.org/web/20080618181901/http://freespace.virgin.net/hugo.elias/graphics/x_water.htm), you can follow `rainTexture` to see how it's used here.

### Performance

Content presented to the user is at most 1 frame old, it takes less than 1ms to render 4k frame on my M1 Max so in theory even 480hz display wouldn't leg behind (at great cost to GPU & CPU of course).

### Why?

As a kid I was using ubuntu (8.04) with [compiz-fusion](https://www.compiz-fusion.org). It would crash often on my radeon x1050, but I kept it for all the awesome effecs. Especially [rain](https://www.youtube.com/watch?v=1ZKmQS_MNAg).
It's been a while since I've used linux and I'm not thinking of switching back, but I wanted some nostalgia.
