# D Video Player — contexto del proyecto

Lee este archivo al empezar cada sesión y actualízalo al terminar.

## Objetivo
Reproductor de video personal para iPhone (iOS 27), sin publicidad. Los videos son MP4.

Funciones obligatorias:
1. Evitar que la pantalla se apague mientras se reproduce (`UIApplication.shared.isIdleTimerDisabled`).
2. Un toque en la pantalla = play/pause.
3. Mantener presionado y arrastrar hacia los lados = cambiar el tiempo del video (scrub).

## Entorno de Daniel
- PC con Windows 11 (sin Mac), iPhone 15 Pro Max (iOS 27), cuenta de desarrollador de Apple **gratuita**.
- Un Atajo de iOS refresca las apps cada 2 días, así que el vencimiento de 7 días no es problema.
- Ya instalados en el PC: Git, GitHub CLI (sesión como `misterdan100`), Node, iTunes, iLoader.
- Daniel se comunica en español.

## Arquitectura de compilación (no hay Xcode local)
1. Se edita el código en `C:\dev\d_video_player`.
2. `git push` a `main` dispara `.github/workflows/build-ipa.yml` en un runner `xcode-27` (Xcode 27, Apple Silicon).
3. El workflow genera el proyecto con **XcodeGen** (`project.yml`; el `.xcodeproj` NO se versiona), compila **sin firmar** y publica `DVideoPlayer.ipa` en el Release `latest` y como artefacto.
4. El `.ipa` se firma e instala en el iPhone con iLoader (desde el PC) o SideStore (desde el iPhone).
5. **Regla fija (pedida por Daniel)**: después de cada build en verde, el asistente descarga el `.ipa` a la carpeta del repo (`gh release download latest -p DVideoPlayer.ipa --clobber` en `C:\dev\d_video_player`), para que quede listo para iLoader sin pasos manuales.

Comandos útiles:
- Lanzar compilación manual: `gh workflow run build-ipa.yml`
- Ver estado: `gh run list --limit 5` / `gh run view <id> --json status,conclusion`
- Ver errores: `gh run view --log-failed`
- Descargar el .ipa: `gh release download latest -p DVideoPlayer.ipa --clobber`
- Ojo desde Cowork: el puente al PC corta las respuestas a los ~60 s; en vez de `gh run watch`, sondear con `gh run view` en llamadas cortas (con `Start-Sleep` de ≤40 s).

## Decisiones
- Swift + SwiftUI, `AVPlayer` nativo (MP4/H.264/HEVC). Sin librerías de terceros para evitar fallos de compilación remota.
- Swift language mode 5.0 (evita errores de concurrencia estricta). Deployment target iOS 18.0.
- Bundle ID: `com.misterdan100.dvideoplayer`. Sin entitlements (cuenta gratuita).
- `UIFileSharingEnabled` activo: la carpeta de la app aparece en Archivos para copiar videos.
- Sesión 1: el video se abre con `.fileImporter` (security-scoped URL), se reproduce con `AVPlayerLayer` propio (sin `AVPlayerViewController`) para controlar los gestos. Audio con categoría `.playback` (suena aunque el iPhone esté en silencio). Al terminar el video: vuelve al inicio en pausa.
- Sesión 2 (elecciones de Daniel): scrub con **seek en vivo** (el video salta mientras se arrastra) y **sensibilidad fija** (ancho completo de pantalla ≈ 90 s; constante `secondsPerFullWidth` en `PlayerScreen.swift`).
- Sesión 2 (implementación): los gestos viven en `VideoLayerView` con reconocedores **UIKit** (`UITapGestureRecognizer` + `UILongPressGestureRecognizer` de 0.3 s) — el primer intento con `LongPressGesture.sequenced(DragGesture)` de SwiftUI NO se activaba en el iPhone. El arrastre se reporta como fracción del ancho de la vista (rotación OK). Al activarse hay háptica y se pausa el video; al soltar reanuda si estaba reproduciendo. Seek con tolerancia cero y cola de 1 pendiente (`requestSeek`/`performNextSeek`) para no saturar `AVPlayer`. Indicador en pantalla: tiempo destino grande + delta (±). Se clampa entre 0 y duración−0.1 s.
- Los controles (X y tiempo) respetan el safe area: antes la X quedaba debajo del Dynamic Island y no recibía toques.
- La pantalla inicial muestra la versión instalada (`CFBundleShortVersionString` + `CFBundleVersion`, declarados explícitos en el Info.plist generado) para verificar qué build corre.
- Sesión 3 (elecciones de Daniel): velocidad de reproducción, lista de videos, **panel de controles reposicionable** (arriba o lateral, porque a veces mira videos con un piano en la parte inferior) y estilo **Liquid Glass** de iOS 26/27.
- Sesión 3 (implementación):
  - **Velocidad**: menú en el panel con 0.25 / 0.4 / 0.5 / 0.7 / 0.8 / 1 / 1.25 / 1.5 / 2× (las lentas las pidió Daniel para videos de piano; el 0.75 original se reemplazó por 0.7 y 0.8). Se usa `player.defaultRate` (iOS 16+), así `play()` siempre reanuda a la velocidad elegida (tras pausa o scrub). Persistida en `@AppStorage("playbackSpeed")`.
  - **Panel reposicionable**: enum `PanelPosition` (top/bottom/leading/trailing), persistida en `@AppStorage("panelPosition")`, por defecto **arriba**. El panel es una cápsula con X, tiempo, velocidad y un menú de posición (ícono de flechas); en los laterales se vuelve vertical (`AnyLayout`) y el tiempo se apila. Durante el scrub el panel se atenúa (opacity 0.25).
  - **Liquid Glass**: modificador propio `liquidGlass(in:interactive:)` que usa `.glassEffect(.regular/.regular.interactive(), in:)` bajo `#available(iOS 26.0, *)` y cae a fondo negro translúcido en iOS < 26. Aplicado al panel y al indicador de scrub. El resto de la UI (lista, botones) toma el look nuevo automáticamente al compilar con el SDK de Xcode 27.
  - **Lista de videos**: la pantalla inicial es un `NavigationStack` con `List` de los MP4/M4V/MOV en Documents (la carpeta "D Video Player" de Archivos), con nombre, tamaño y fecha; tocar = reproducir (sin security scope). Pull-to-refresh, estado vacío con instrucciones (`ContentUnavailableView`), botón de carpeta en la toolbar para abrir de otra ubicación con `.fileImporter`, y la versión abajo.

## Estructura del código (Sources/)
- `DVideoPlayerApp.swift` — entry point.
- `ContentView.swift` — biblioteca: lista de videos de Documents (`VideoLibrary.scan()`, struct `VideoFile`), estado vacío, `.fileImporter` para otras carpetas, alerta de error, texto de versión; `VideoSelection` maneja el acceso security-scoped.
- `PlayerScreen.swift` — pantalla de reproducción: play/pause, scrub, velocidad (`defaultRate`), panel reposicionable (`PanelPosition`), indicador de tiempo, `isIdleTimerDisabled`, helper `liquidGlass`.
- `VideoLayerView.swift` — `UIViewRepresentable` con `AVPlayerLayer` + gestos UIKit (tap y mantener+arrastrar) que reporta por callbacks a `PlayerScreen`.

## Plan por sesiones
- [x] **Sesión 0** — Pipeline: repo, XcodeGen, workflow, app "Hola mundo" instalada en el iPhone.
- [x] **Sesión 1** — Reproductor base: abrir video desde Archivos, `AVPlayer` + `AVPlayerLayer` en SwiftUI, pantalla siempre encendida, tap = play/pause.
- [x] **Sesión 2** — Gesto de scrub: mantener + arrastrar horizontal, indicador de tiempo en pantalla, sensibilidad, modo horizontal.
- [x] **Sesión 3** — Velocidad de reproducción, lista de videos, panel reposicionable (arriba/abajo/laterales), Liquid Glass.
- [ ] **Pendientes posibles** — Recordar posición por video, imagen en imagen (PiP; ojo: con cuenta gratuita el background puede no funcionar), borrar videos desde la lista.

## Estado actual
- Sesión 3 VALIDADA en el iPhone (2026-10-20): Daniel probó la v0.5.0 y dijo que "funciona muy bien" (velocidad, lista, panel reposicionable, Liquid Glass).
- **v0.5.1 (build 6) VALIDADA en el iPhone (2026-10-20)**: Daniel la instaló y confirmó que funciona perfecto (velocidades lentas 0.25 / 0.4 / 0.7 / 0.8 incluidas). Commit `f847b10`, run 39481395603.
- No hay pendientes; próximas ideas en "Pendientes posibles" del plan.

## Problemas conocidos
- Los archivos de `.github/workflows` están protegidos para las herramientas remotas: el asistente no puede escribirlos. Si hay que cambiar el workflow, dejar el archivo en una carpeta temporal y pedirle a Daniel que lo mueva a `.github\workflows\`.
- El script del workflow elige la Xcode más reciente instalada (hoy una beta). Si una beta da problemas, fijarlo a la versión estable.
- iLoader falló al iniciar sesión con el Apple ID (error 502 del servidor anisette `new.ani.sidestore.io`, caído temporalmente). Si se repite: esperar, o instalar el .ipa desde el iPhone con SideStore.
- GitHub Actions avisa que `actions/checkout@v4` y `upload-artifact@v4` usan Node 20 (deprecado); no bloquea nada, pero en algún momento conviene subirlas a v5.
- `gh run watch` desde Cowork se corta a los ~60 s (límite del puente al PC); usar sondeos cortos con `gh run view`.
