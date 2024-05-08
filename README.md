# dszcz

As a kid I was using ubuntu (8.04) with [compiz-fusion](https://www.compiz-fusion.org). It would crash often on my radeon x1050, but I kept it for all the awesome effecs. Especially [rain](https://www.youtube.com/watch?v=1ZKmQS_MNAg).
It's been a while since I've used linux and I'm not thinking of switching back, but it should be possible to bring a little of that to macos.

### Initial implementation plan
Existence of apps like [iSnow](https://apps.apple.com/pl/app/isnow/id565963412) and [lo-rain](https://lo.cafe/lo-rain) shows that it's possible to overlay objects on the screen. Both apps render translucent objects over UI and they don't affect what is shown in the app, but it should be possible to grab screenshot [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), feed it to [MetalKit](https://developer.apple.com/documentation/metalkit) and run shaders on it before presenting modified image to the user. 16ms will probably be max time to process, anything more than 1 frame behind might be noticeable with normal use.
