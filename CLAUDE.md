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
- Ver estado: `gh run list --limit 5` / `gh run watch`
- Ver errores: `gh run view --log-failed`
- Descargar el .ipa: `gh release download latest -p DVideoPlayer.ipa --clobber`

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

## Estructura del código (Sources/)
- `DVideoPlayerApp.swift` — entry point.
- `ContentView.swift` — pantalla inicial, botón "Abrir video" + `.fileImporter`, texto de versión instalada; `VideoSelection` maneja el acceso security-scoped.
- `PlayerScreen.swift` — pantalla de reproducción: lógica de play/pause y scrub, indicador de tiempo, botón cerrar (dentro del safe area), `isIdleTimerDisabled`.
- `VideoLayerView.swift` — `UIViewRepresentable` con `AVPlayerLayer` + gestos UIKit (tap y mantener+arrastrar) que reporta por callbacks a `PlayerScreen`.

## Plan por sesiones
- [x] **Sesión 0** — Pipeline: repo, XcodeGen, workflow, app "Hola mundo" instalada en el iPhone.
- [x] **Sesión 1** — Reproductor base: abrir video desde Archivos, `AVPlayer` + `AVPlayerLayer` en SwiftUI, pantalla siempre encendida, tap = play/pause.
- [x] **Sesión 2** — Gesto de scrub: mantener + arrastrar horizontal, indicador de tiempo en pantalla, sensibilidad, modo horizontal.
- [ ] **Sesión 3** (opcional) — Recordar posición, velocidad, lista de videos, imagen en imagen.

## Estado actual
- Sesión 2 corregida (2026-10-20): Daniel probó en el iPhone y ni el scrub ni la X funcionaban. Se reescribió el gesto con UIKit, se movieron los controles al safe area y se agregó el texto de versión. **v0.4.0 (build 4)**, commit `82c11d2`, run 39477511114 en verde (~58 s). El `.ipa` nuevo ya está en el Release `latest`.
- Falta validar en el iPhone con v0.4.0: que la pantalla inicial diga "v0.4.0 (build 4)", reproducción, tap = play/pause, pantalla siempre encendida, la X cierra, y el scrub (mantener 0.3 s + arrastrar: háptica, indicador de tiempo, seek en vivo, reanudar al soltar, también en horizontal). Si la sensibilidad de 90 s/pantalla no le gusta, ajustar `secondsPerFullWidth`.
- Nota: el problema del scrub pudo ser también de instalación (no sabemos qué versión probó); con el texto de versión ya se puede verificar.
- Siguiente: validación en el iPhone y, si todo bien, Sesión 3 (opcional).

## Problemas conocidos
- Los archivos de `.github/workflows` están protegidos para las herramientas remotas: el asistente no puede escribirlos. Si hay que cambiar el workflow, dejar el archivo en una carpeta temporal y pedirle a Daniel que lo mueva a `.github\workflows\`.
- El script del workflow elige la Xcode más reciente instalada (hoy una beta). Si una beta da problemas, fijarlo a la versión estable.
- iLoader falló al iniciar sesión con el Apple ID (error 502 del servidor anisette `new.ani.sidestore.io`, caído temporalmente). Si se repite: esperar, o instalar el .ipa desde el iPhone con SideStore.
- GitHub Actions avisa que `actions/checkout@v4` y `upload-artifact@v4` usan Node 20 (deprecado); no bloquea nada, pero en algún momento conviene subirlas a v5.
