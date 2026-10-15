/// Número de tiempo ("1… 8") que flota sobre el maniquí y avanza al ritmo de
/// la animación.
///
/// Es un hotspot de `<model-viewer>`: un elemento HTML anclado a un punto 3D
/// que el propio visor reproyecta cada fotograma. Por ser DOM y no geometría,
/// siempre mira a la cámara (billboard real, sin girar nada a mano), se ve
/// nítido a cualquier zoom y no añade mallas, texturas ni draw calls a WebGL.
///
/// El tiempo se lee de `mv.currentTime` (tiempo de la animación), así que el
/// conteo sigue al bucle y al slider de velocidad sin reloj propio. El DOM
/// solo se toca al cambiar de tiempo (≈2 veces por segundo) y el pulso es una
/// Web Animation de `transform`/`opacity`, que va por el compositor. Con la
/// animación en pausa (app en segundo plano) el bucle de rAF se detiene.
class BeatCounter {
  BeatCounter._();

  /// Altura del número sobre la base de la pista (el maniquí mide ≈1.69 m).
  static const String _anchor = '0m 2m 0m';

  static const String html = '''
    <div slot="hotspot-beat" class="bg-beat" data-position="$_anchor">
      <span class="bg-beat-num"></span>
    </div>
  ''';

  static const String css = '''
    .bg-beat {
      pointer-events: none;
      display: flex;
      align-items: center;
      justify-content: center;
      width: 0;
      height: 0;
    }
    .bg-beat-num {
      font: 900 52px/1 system-ui, -apple-system, Roboto, sans-serif;
      color: #FFFFFF;
      text-shadow: 0 0 18px rgba(255, 138, 61, 0.9), 0 3px 8px rgba(0, 0, 0, 0.55);
      will-change: transform, opacity;
    }
    .bg-beat-num:empty { display: none; }
    /* 1 y 5: arranque de cada medio compás. */
    .bg-beat-num.accent {
      color: #69F0AE;
      text-shadow: 0 0 22px rgba(105, 240, 174, 0.95), 0 3px 8px rgba(0, 0, 0, 0.55);
    }
  ''';

  /// Script que arranca el conteo. Idempotente por elemento; espera a que
  /// `<model-viewer>` exista (en web el platform view se monta después).
  static String script(int beatsPerLoop) => '''
    (function () {
      var BEATS = $beatsPerLoop;
      function find(root) {
        var m = root.querySelector('model-viewer'); if (m) return m;
        var all = root.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          if (all[i].shadowRoot) { m = find(all[i].shadowRoot); if (m) return m; }
        }
        return null;
      }
      function start(mv) {
        var el = mv.querySelector('.bg-beat-num');
        // Marca en el elemento, no en window: en web el documento es el de la
        // app y sobrevive entre visitas al visor.
        if (!el || mv.__bgBeat) return;
        mv.__bgBeat = true;
        var last = -1, raf = 0;
        function show(b) {
          // Los ciclos de 16 tiempos (dos frases) se cuentan 1…8, 1…8.
          el.textContent = (b % 8) + 1;
          el.classList.toggle('accent', b % 4 === 0);
          if (el.animate) {
            el.animate(
              [{ transform: 'scale(1.45)', opacity: 0.35 },
               { transform: 'scale(1)', opacity: 1 }],
              { duration: 240, easing: 'cubic-bezier(.2,.9,.3,1.3)' });
          }
        }
        function tick() {
          raf = 0;
          var d = mv.duration;
          if (d > 0) {
            var t = mv.currentTime % d;
            if (t < 0) t += d;
            var b = Math.min(BEATS - 1, Math.floor(t * BEATS / d));
            if (b !== last) { last = b; show(b); }
          }
          if (!mv.paused) raf = requestAnimationFrame(tick);
        }
        function run() { if (!raf) raf = requestAnimationFrame(tick); }
        mv.addEventListener('play', run);
        mv.addEventListener('load', function () { last = -1; run(); });
        run();
      }
      (function wait(n) {
        var mv = find(document);
        if (mv) start(mv);
        else if (n > 0) setTimeout(function () { wait(n - 1); }, 100);
      })(50);
    })();
  ''';
}
