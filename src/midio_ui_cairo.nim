import math, sugar, options, colors
import midio_ui
import sdl2
import cairo

discard sdl2.init(INIT_EVERYTHING)

const
  rmask = uint32 0x000000ff
  gmask = uint32 0x0000ff00
  bmask = uint32 0x00ff0000
  amask = uint32 0xff000000

var
  scale = 2.0
  w: int32 = 1000
  h: int32 = 1000
  surface = imageSurfaceCreate(FORMAT_ARGB32, w, h)
  window: WindowPtr = createWindow("Real time SDL/Cairo example", 100, 100, cint w, cint h, SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE)
  render: RendererPtr = createRenderer(window, -1, 0)
  mainSurface: SurfacePtr = createRGBSurface(0, cint w, cint h, 32, rmask, gmask, bmask, amask)

var
  mainTexture: TexturePtr

type
  RenderContext = ref object
    surface: ptr cairo.Context

proc renderSegment(ctx: RenderContext, segment: PathSegment): void =
  case segment.kind
  of PathSegmentKind.MoveTo:
    ctx.surface.moveTo(segment.to.x, segment.to.y )
  of PathSegmentKind.LineTo:
    ctx.surface.lineTo(segment.to.x, segment.to.y )
  of PathSegmentKind.QuadraticCurveTo:
    ctx.surface.curveTo(
      segment.controlPoint.x,
      segment.controlPoint.y,
      segment.point.x,
      segment.point.y,
      segment.point.x,
      segment.point.y
    )
  of PathSegmentKind.Close:
    ctx.surface.closePath()

proc measureText(ctx: RenderContext, text: string): tuple[width: float, height: float] =
  var
    text = text
    extents: TTextExtents
  ctx.surface.textExtents(text, addr extents)
  (extents.width, extents.height)

proc renderText(ctx: RenderContext, colorInfo: Option[ColorInfo], textInfo: TextInfo): void =
  # ctx.fillStyle = colorInfo.map(x => x.fill.get("red")).get("brown")
  # ctx.textAlign = textInfo.alignment
  # ctx.textBaseline = textInfo.textBaseline
  # ctx.fillText(textInfo.text, textInfo.pos.x, textInfo.pos.y)
  ctx.surface.selectFontFace(textInfo.font, FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  ctx.surface.setFontSize(textInfo.fontSize )
  let textColor = colorInfo.map(x => x.fill.get("red")).get("brown")
  let c = parseColor(textColor).extractRgb()
  ctx.surface.setSourceRGBA(float(c.r)/255.0, float(c.g)/255.0, float(c.b)/255.0, 1.0)
  let textSize = ctx.measureText(textInfo.text)
  ctx.surface.moveTo(textInfo.pos.x, textInfo.pos.y  + textSize.height  / 2.0)
  ctx.surface.showText(textInfo.text)

proc renderCircle(ctx: RenderContext, info: CircleInfo): void =
  ctx.surface.arc(info.center.x + info.radius, info.center.y + info.radius, info.radius, 0.0, TAU)

proc renderEllipse(ctx: RenderContext, info: EllipseInfo): void =
  ctx.surface.newPath()
  let
    c = info.center
    r = info.radius
  ctx.surface.arc(c.x, c.y, r.x, info.startAngle, info.endAngle)

proc fillAndStroke(ctx: RenderContext, colorInfo: Option[ColorInfo], strokeInfo: Option[StrokeInfo]): void =
  if strokeInfo.isSome():
    ctx.surface.setLineWidth(strokeInfo.get().width )
  if colorInfo.isSome():
    let ci = colorInfo.get()
    if ci.fill.isSome():
      let c = parseColor(ci.fill.get()).extractRGB()
      ctx.surface.setSourceRGB(float(c.b)/255.0, float(c.g)/255.0, float(c.r)/255.0)
      ctx.surface.fill()
    if ci.stroke.isSome():
      let c = parseColor(ci.stroke.get()).extractRGB()
      ctx.surface.setSourceRGB(float(c.b)/255.0, float(c.g)/255.0, float(c.r)/255.0)
      ctx.surface.stroke()

proc renderPrimitive(ctx: RenderContext, p: Primitive): void =
  case p.kind
  of PrimitiveKind.Container:
    discard
  of PrimitiveKind.Path:
    ctx.surface.newPath()
    for segment in p.segments:
      ctx.renderSegment(segment)
    #ctx.surface.stroke()
    ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
  of PrimitiveKind.Text:
    ctx.renderText(p.colorInfo, p.textInfo)
  of PrimitiveKind.Circle:
    renderCircle(ctx, p.circleInfo)
    ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
  of PrimitiveKind.Ellipse:
    renderEllipse(ctx, p.ellipseInfo)
    ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
  of PrimitiveKind.Rectangle:
    # if p.strokeInfo.isSome():
    #   ctx.lineWidth = p.strokeInfo.get().width
    if p.colorInfo.isSome():
      let b = p.rectangleInfo.bounds
      ctx.surface.rectangle(b.x, b.y, b.width, b.height )
      ctx.surface.fill()
      # let ci = p.colorInfo.get()
      # if ci.fill.isSome():
      #   ctx.fillStyle = ci.fill.get()
      #   ctx.fillRect(b.left, b.top, b.width, b.height)
      # if ci.stroke.isSome():
      #   ctx.strokeStyle = ci.stroke.get()
      #   ctx.strokeRect(b.left, b.top, b.width, b.height)

proc renderPrimitives(ctx: RenderContext, primitive: Primitive, offset: Vec2[float]): void =
  ctx.surface.save()
  if primitive.clipToBounds:
    ctx.surface.newPath()
    let cb = primitive.bounds
    ctx.surface.rectangle(offset.x, offset.y, cb.size.x, cb.size.y )
    ctx.surface.clip()
  ctx.renderPrimitive(primitive)
  for p in primitive.children:
    ctx.renderPrimitives(p, offset + p.bounds.pos)
  ctx.surface.restore()

var evt = sdl2.defaultEvent

proc measureText(text: string, fontSize: float, font: string, baseline: string): Vec2[float] =
  let ctx = RenderContext(
    surface: surface.create()
  )
  let res = ctx.measureText(text)
  vec2(res.width, res.height)


var frameTime: uint32 = 0


proc startApp*(renderFunc: () -> Element): void =
  let context = midio_ui.init(vec2(float(w),float(h)), vec2(scale, scale), measureText, renderFunc)
  let ctx = RenderContext(
    surface: surface.create()
  )

  ctx.surface.scale(scale, scale)
  while true:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        quit(0)
      elif evt.kind == MouseMotion:
        let event = cast[MouseMotionEventPtr](addr(evt))
        context.dispatchPointerMove(float( event.x ), float(event.y))
      elif evt.kind == MouseButtonDown:
        let event = cast[MouseButtonEventPtr](addr(evt))
        context.dispatchPointerDown(float(event.x), float(event.y))
      elif evt.kind == MouseButtonUp:
        let event = cast[MouseButtonEventPtr](addr(evt))
        context.dispatchPointerUp(float(event.x), float(event.y))
      elif evt.kind == WindowEvent:
        var windowEvent = cast[WindowEventPtr](addr(evt))
        if windowEvent.event == WindowEvent_Resized:
          w = windowEvent.data1
          h = windowEvent.data2
          window.setSize(w, h)
          surface = imageSurfaceCreate(FORMAT_ARGB32, w, h)
          mainSurface = createRGBSurface(0, cint w, cint h, 32, rmask, gmask, bmask, amask)
          ctx.surface = surface.create()
          ctx.surface.scale(scale, scale)

          context.dispatchWindowSizeChanged(vec2(float(w), float(h)))
      elif evt.kind == KEY_DOWN:
        let key = evt.key()
        echo key.type
        let keyCode = getKeyFromScancode(key.keysym.scancode)
        let scanCodeName = getScanCodeName(key.keysym.scancode)
        # TODO: keycode is not cross platform atm
        context.dispatchKeyDown(keyCode, $scanCodeName)


    let now = getTicks()
    let dt = float(now - frameTime)
    frameTime = now

    let primitive = midio_ui.render(context, dt)

    #echo "SURFACE: ", surface.w, ",", surface.h

    let c = parseColor("#1b2a39").extractRgb()
    ctx.surface.setSourceRGB(float(c.b)/255.0, float(c.g)/255.0, float(c.r)/255.0)
    ctx.surface.rectangle(0, 0, float(w), float(h))
    ctx.surface.fill()
    if primitive.isSome():
      ctx.renderPrimitives(primitive.get(), vec2(0.0))

    var dataPtr = surface.getData()
    mainSurface.pixels = dataPtr
    mainTexture = render.createTextureFromSurface(mainSurface)
    render.copy(mainTexture, nil, nil)
    render.present()
    mainTexture.destroy()
