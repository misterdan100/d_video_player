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

## Plan por sesiones
- [x] **Sesión 0** — Pipeline: repo, XcodeGen, workflow, app "Hola mundo" instalada en el iPhone.
- [ ] **Sesión 1** — Reproductor base: abrir video desde Archivos, `AVPlayer` + `AVPlayerLayer` en SwiftUI, pantalla siempre encendida, tap = play/pause.
- [ ] **Sesión 2** — Gesto de scrub: mantener + arrastrar horizontal, indicador de tiempo en pantalla, sensibilidad, modo horizontal.
- [ ] **Sesión 3** (opcional) — Recordar posición, velocidad, lista de videos, imagen en imagen.

## Estado actual
- Sesión 0 COMPLETA (2026-10-20): el pipeline funciona de punta a punta. Repo: https://github.com/misterdan100/d_video_player. La compilación tarda ~47 s en el runner `xcode-27` (Xcode 27.2 beta 2, SDK iphoneos27.2) y la app "Hola mundo" ya está instalada y abre en el iPhone mostrando versión, build y versión de iOS.
- Siguiente: Sesión 1 (reproductor base).

## Problemas conocidos
- Los archivos de `.github/workflows` están protegidos para las herramientas remotas: el asistente no puede escribirlos. Si hay que cambiar el workflow, dejar el archivo en una carpeta temporal y pedirle a Daniel que lo mueva a `.github\workflows\`.
- El script del workflow elige la Xcode más reciente instalada (hoy una beta). Si una beta da problemas, fijarlo a la versión estable.
- iLoader falló al iniciar sesión con el Apple ID (error 502 del servidor anisette `new.ani.sidestore.io`, caído temporalmente). Si se repite: esperar, o instalar el .ipa desde el iPhone con SideStore.