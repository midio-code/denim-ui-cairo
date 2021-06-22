import math, sugar, options, colors, strutils, strformat
import denim_ui
import sdl2
import cairo

discard sdl2.init(INIT_EVERYTHING)

const
  rmask = uint32 0x000000ff
  gmask = uint32 0x0000ff00
  bmask = uint32 0x00ff0000
  amask = uint32 0xff000000

var
  scale = 1.0
  w: int32 = 1500
  h: int32 = 1500
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
    ctx.surface.moveTo(segment.to.x, segment.to.y)
  of PathSegmentKind.LineTo:
    ctx.surface.lineTo(segment.to.x, segment.to.y)
  of PathSegmentKind.BezierCurveTo:
    ctx.surface.curveTo(
      segment.bezierInfo.controlPoint1.x,
      segment.bezierInfo.controlPoint1.y,
      segment.bezierInfo.controlPoint2.x,
      segment.bezierInfo.controlPoint2.y,
      segment.bezierInfo.point.x,
      segment.bezierInfo.point.y
    )
  of PathSegmentKind.QuadraticCurveTo:
    ctx.surface.curveTo(
      segment.quadraticInfo.controlPoint.x,
      segment.quadraticInfo.controlPoint.y,
      segment.quadraticInfo.controlPoint.x,
      segment.quadraticInfo.controlPoint.y,
      segment.quadraticInfo.point.x,
      segment.quadraticInfo.point.y
    )
  of PathSegmentKind.Close:
    ctx.surface.closePath()

proc measureText(ctx: RenderContext, text: string, fontSize: float, font: string): tuple[width: float, height: float] =
  var
    text = text
    extents: TTextExtents

  ctx.surface.selectFontFace(font, FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  ctx.surface.setFontSize(fontSize)

  ctx.surface.textExtents(text, addr extents)
  (extents.width * scale, extents.height * scale)

proc renderText(ctx: RenderContext, bounds: Bounds, colorInfo: Option[ColorInfo], textInfo: TextInfo): void =
  ctx.surface.selectFontFace(textInfo.fontFamily, FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  ctx.surface.setFontSize(textInfo.fontSize )
  let textColor = colorInfo.map(x => x.fill.get(colRed)).get(colBrown)
  assert(textColor.kind == ColorStyleKind.Solid)
  ctx.surface.setSourceRGBA(
    float(textColor.color.r)/255.0,
    float(textColor.color.g)/255.0,
    float(textColor.color.b)/255.0,
    float(textColor.color.a)/255.0
  )
  let textSize = ctx.measureText($textInfo.text, textInfo.fontSize, $textInfo.fontFamily)
  ctx.surface.moveTo(bounds.pos.x, bounds.pos.y)#  + textSize.height  / 2.0)
  ctx.surface.showText(textInfo.text)

proc renderCircle(ctx: RenderContext, info: CircleInfo): void =
  ctx.surface.arc(info.radius, info.radius, info.radius, 0.0, TAU)

proc renderEllipse(ctx: RenderContext, info: EllipseInfo): void =
  ctx.surface.newPath()
  let
    r = info.radius
  ctx.surface.arc(0.0, 0.0, r.x, info.startAngle, info.endAngle)

proc fillAndStroke(ctx: RenderContext, colorInfo: Option[ColorInfo], strokeInfo: Option[StrokeInfo]): void =
  if strokeInfo.isSome():
    ctx.surface.setLineWidth(strokeInfo.get().width)
  if colorInfo.isSome():
    let ci = colorInfo.get()
    if ci.fill.isSome():
      if ci.fill.get.kind == ColorStyleKind.Solid:
        let c = ci.fill.get().color
        ctx.surface.setSourceRGB(float(c.b)/255.0, float(c.g)/255.0, float(c.r)/255.0)
        ctx.surface.fill_preserve()
    if ci.stroke.isSome():
      if ci.stroke.get.kind == ColorStyleKind.Solid:
        let c = ci.stroke.get().color
        ctx.surface.setSourceRGB(float(c.b)/255.0, float(c.g)/255.0, float(c.r)/255.0)
        ctx.surface.stroke()

proc renderPrimitive(ctx: RenderContext, p: Primitive): void =
  echo "rendering prim: ", p.kind
  case p.kind
  of PrimitiveKind.Container:
    discard
  of PrimitiveKind.Image:
    discard
  of PrimitiveKind.Path:
    case p.pathInfo.kind:
      of PathInfoKind.Segments:
        ctx.surface.newPath()
        for segment in p.pathInfo.segments:
          ctx.renderSegment(segment)
        ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
      else:
        echo("Path string data not supported in Cairo backend.")
    #ctx.surface.stroke()
  of PrimitiveKind.Text:
    ctx.renderText(p.bounds, p.colorInfo, p.textInfo)
  of PrimitiveKind.Circle:
    renderCircle(ctx, p.circleInfo)
    ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
  of PrimitiveKind.Ellipse:
    renderEllipse(ctx, p.ellipseInfo)
    ctx.fillAndStroke(p.colorInfo, p.strokeInfo)
  of PrimitiveKind.Rectangle:
    if p.colorInfo.isSome():
      let b = p.rectangleInfo.bounds
      ctx.surface.rectangle(b.x, b.y, b.width, b.height )
      ctx.surface.fill()
    if p.strokeInfo.isSome():
      ctx.surface.setLineWidth(p.strokeInfo.get().width)
      #ctx.lineWidth = p.strokeInfo.get().width
      ctx.surface.stroke()
      # let ci = p.colorInfo.get()
      # if ci.fill.isSome():
      #   ctx.fillStyle = ci.fill.get()
      #   ctx.fillRect(b.left, b.top, b.width, b.height)
      # if ci.stroke.isSome():
      #   ctx.strokeStyle = ci.stroke.get()
      #   ctx.strokeRect(b.left, b.top, b.width, b.height)

proc renderPrimitives(ctx: RenderContext, primitive: Primitive, offset: Vec2[float]): void =
  ctx.surface.save()
  ctx.surface.translate(primitive.bounds.x, primitive.bounds.y)
  for transform in  primitive.transform:
    case transform.kind:
      of Scaling:
        ctx.surface.scale(
          transform.scale.x,
          transform.scale.y
        )
      of Translation:
        ctx.surface.translate(transform.translation.x, transform.translation.y)
      of Rotation:
        ctx.surface.rotate(transform.rotation)
  if primitive.clipToBounds:
    ctx.surface.newPath()
    let cb = primitive.bounds
    ctx.surface.rectangle(0.0, 0.0, cb.size.x, cb.size.y )
    ctx.surface.clip()

  ctx.renderPrimitive(primitive)
  for p in primitive.children:
    ctx.renderPrimitives(p, offset + p.bounds.pos)
  ctx.surface.restore()

var evt = sdl2.defaultEvent

proc measureTextImpl(text: string, fontSize: float, fontFamily: string, fontWeight: int, baseline: string): Vec2[float] =
  let ctx = RenderContext(
    surface: surface.create()
  )
  let res = ctx.measureText(text, fontSize, fontFamily)
  vec2(res.width, res.height)


var frameTime: uint32 = 0

proc hitTestPath(self: Element, pathProps: PathProps, point: denim_ui.Point): bool =
  # TODO: Implement hit test for path
  false

proc requestRerender() =
  discard

proc startApp*(renderFunc: () -> Element): void =
  let context = denim_ui.init(
    vec2(float(w), float(h)),
    vec2(scale, scale),
    measureTextImpl,
    hitTestPath,
    requestRerender,
    renderFunc,
    NativeElements(
      createTextInput: proc(props: (ElementProps, TextInputProps), children: seq[Element] = @[]): TextInput =
        let textProps = props[1]
        cast[TextInput](createText(
          (
            props[0],
            TextProps(
              text: textProps.text,
              fontSize: textProps.fontSize,
              color: textProps.color,
            )
          )
        ))
    ),
    proc(c: Cursor): void = discard
  )
  let ctx = RenderContext(
    surface: surface.create()
  )

  proc buttonIndex(index: int): PointerIndex =
    case index:
      of 1: PointerIndex.Primary
      of 3: PointerIndex.Secondary
      else:
        echo &"Mouse button {index} not supported"
        PointerIndex.Primary

  ctx.surface.scale(scale, scale)
  var currentPointerPos = zero()
  while true:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        quit(0)
      elif evt.kind == MouseMotion:
        let event = cast[MouseMotionEventPtr](addr(evt))
        currentPointerPos = vec2(float(event.x), float(event.y))
        context.dispatchPointerMove(float(event.x), float(event.y))
      elif evt.kind == MouseButtonDown:
        let event = cast[MouseButtonEventPtr](addr(evt))
        # TODO: Implement pointer index
        context.dispatchPointerDown(float(event.x), float(event.y), buttonIndex(int(event.button)))
      elif evt.kind == MouseButtonUp:
        let event = cast[MouseButtonEventPtr](addr(evt))
        # TODO: Implement pointer index
        context.dispatchPointerUp(float(event.x), float(event.y), buttonIndex(int(event.button)))
      elif evt.kind == MouseWheel:
        let event = cast[MouseWheelEventPtr](addr(evt))
        # TODO: Implement pointer index
        context.dispatchWheel(currentPointerPos.x, currentPointerPos.y, float(event.x), float(event.y), 0.0, WheelDeltaUnit.Line)
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
        context.dispatchKeyDown(toLowerAscii($scanCodeName), @[])
      elif evt.kind == KEY_UP:
        let key = evt.key()
        echo key.type
        let keyCode = getKeyFromScancode(key.keysym.scancode)
        let scanCodeName = getScanCodeName(key.keysym.scancode)
        # TODO: keycode is not cross platform atm
        context.dispatchKeyUp(toLowerAscii($scanCodeName), @[])


    let now = getTicks()
    let dt = float(now - frameTime)
    frameTime = now

    echo "Updating: ", dt
    context.update(dt)
    let primitive = denim_ui.render(context)
    echo "Prim: ", primitive.get.bounds

    let c = denim_ui.parseColor("#ffffff")
    ctx.surface.setSourceRGB(
      float(c.b)/255.0,
      float(c.g)/255.0,
      float(c.r)/255.0
    )
    ctx.surface.rectangle(0, 0, float(w), float(h))
    ctx.surface.fill()
    if primitive.isSome():
      ctx.renderPrimitives(primitive.get(), vec2(500.0))

    var dataPtr = surface.getData()
    mainSurface.pixels = dataPtr
    mainTexture = render.createTextureFromSurface(mainSurface)
    render.copy(mainTexture, nil, nil)
    render.present()
    mainTexture.destroy()
