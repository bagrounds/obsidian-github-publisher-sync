void function () {
  var DORMANT = 0, ACTIVE = 1, OVER = 2;
  var N = 14;
  var state, score, health, time, awakenT, animId, cleanupResize;
  var player, elements, canvas, ctx, W, H;

  function init() {
    var box = document.getElementById('valence-game');
    if (!box) return null;
    box.innerHTML = '';
    canvas = document.createElement('canvas');
    canvas.style.cssText = 'display:block;width:100%;border-radius:12px;touch-action:none;cursor:crosshair;';
    box.appendChild(canvas);
    ctx = canvas.getContext('2d');

    state = DORMANT; score = 0; health = 100; time = 0; awakenT = 0;
    player = { x: 0, y: 0, tx: 0, ty: 0, r: 14, down: false };
    elements = [];

    function resize() {
      W = canvas.clientWidth;
      H = Math.min(Math.round(W * 1.1), Math.round(window.innerHeight * 0.72));
      canvas.width = W; canvas.height = H;
      player.x = player.tx = W / 2;
      player.y = player.ty = H / 2;
    }
    resize();
    window.addEventListener('resize', resize);
    cleanupResize = function () { window.removeEventListener('resize', resize); };

    for (var i = 0; i < N; i++) {
      var e = spawn();
      e.x = Math.random() * W;
      e.y = Math.random() * H;
    }

    canvas.addEventListener('touchstart', onDown, { passive: false });
    canvas.addEventListener('touchmove', onMove, { passive: false });
    canvas.addEventListener('touchend', onUp, { passive: false });
    canvas.addEventListener('mousedown', onDown);
    canvas.addEventListener('mousemove', function (ev) { if (player.down) onMove(ev); });
    canvas.addEventListener('mouseup', onUp);

    animId = requestAnimationFrame(loop);
    return cleanup;
  }

  function cleanup() {
    cancelAnimationFrame(animId);
    if (cleanupResize) cleanupResize();
  }

  function pos(ev) {
    var r = canvas.getBoundingClientRect(), t = ev.touches ? ev.touches[0] : ev;
    return { x: t.clientX - r.left, y: t.clientY - r.top };
  }

  function onDown(ev) {
    ev.preventDefault();
    var p = pos(ev);
    player.tx = p.x; player.ty = p.y; player.down = true;
    if (state === DORMANT) { state = ACTIVE; awakenT = time; }
    if (state === OVER) { state = DORMANT; health = 100; score = 0; player.down = false; }
  }
  function onMove(ev) { ev.preventDefault(); var p = pos(ev); player.tx = p.x; player.ty = p.y; }
  function onUp(ev) { ev.preventDefault(); player.down = false; }

  function spawn() {
    var good = Math.random() > 0.38;
    var side = Math.random() * 4 | 0, sp = 0.25 + Math.random() * 0.45;
    var x, y, vx, vy;
    if (side === 0) { x = -12; y = Math.random() * H; vx = sp; vy = (Math.random() - 0.5) * sp; }
    else if (side === 1) { x = W + 12; y = Math.random() * H; vx = -sp; vy = (Math.random() - 0.5) * sp; }
    else if (side === 2) { x = Math.random() * W; y = -12; vx = (Math.random() - 0.5) * sp; vy = sp; }
    else { x = Math.random() * W; y = H + 12; vx = (Math.random() - 0.5) * sp; vy = -sp; }
    var el = { x: x, y: y, vx: vx, vy: vy, r: 5 + Math.random() * 6, good: good, ph: Math.random() * 6.28, fr: 0.5 + Math.random() * 1.5 };
    elements.push(el);
    return el;
  }

  function lerp3(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
  function rgb(c) { return 'rgb(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ')'; }
  function rgba(c, a) { return 'rgba(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ',' + a + ')'; }

  var GRAY = [110, 110, 120];
  var GOOD = [[42, 230, 160], [70, 200, 210], [100, 240, 180]];
  var BAD = [[240, 65, 80], [230, 100, 90], [200, 50, 60]];
  var DIM = [95, 95, 105], BRIGHT = [255, 245, 210];

  function pickColor(el) {
    var idx = Math.abs(Math.round(el.ph * 10)) % 3;
    return el.good ? GOOD[idx] : BAD[idx];
  }

  function loop() {
    time += 1 / 60;
    var tf = state >= ACTIVE ? Math.min(1, (time - awakenT) * 0.7) : 0;

    if (state === ACTIVE && player.down) {
      player.x += (player.tx - player.x) * 0.045;
      player.y += (player.ty - player.y) * 0.045;
    }
    player.x += Math.sin(time * 2.1) * 0.25;
    player.y += Math.cos(time * 1.7) * 0.25;

    for (var i = elements.length - 1; i >= 0; i--) {
      var el = elements[i];
      el.x += el.vx + Math.sin(time * el.fr + el.ph) * 0.35;
      el.y += el.vy + Math.cos(time * el.fr * 0.7 + el.ph) * 0.35;
      if (el.x < -40 || el.x > W + 40 || el.y < -40 || el.y > H + 40) { elements.splice(i, 1); spawn(); continue; }
      if (state === ACTIVE) {
        var dx = el.x - player.x, dy = el.y - player.y, d = Math.sqrt(dx * dx + dy * dy);
        if (d < player.r + el.r) {
          if (el.good) score++; else health = Math.max(0, health - 12);
          elements.splice(i, 1); spawn();
          if (health <= 0) state = OVER;
        }
      }
    }
    while (elements.length < N) spawn();

    ctx.fillStyle = '#080820';
    ctx.fillRect(0, 0, W, H);

    for (var i = 0; i < elements.length; i++) {
      var el = elements[i], pulse = 1 + Math.sin(time * 3 + el.ph) * 0.12, r = el.r * pulse;
      var col = lerp3(GRAY, pickColor(el), tf);
      var g = ctx.createRadialGradient(el.x, el.y, 0, el.x, el.y, r * 2.5);
      g.addColorStop(0, rgba(col, 0.3)); g.addColorStop(1, rgba(col, 0));
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(el.x, el.y, r * 2.5, 0, 6.28); ctx.fill();
      ctx.globalAlpha = 0.85; ctx.fillStyle = rgb(col); ctx.beginPath(); ctx.arc(el.x, el.y, r, 0, 6.28); ctx.fill(); ctx.globalAlpha = 1;
    }

    var pc = lerp3(DIM, BRIGHT, tf), pp = 1 + Math.sin(time * 2) * 0.07, pr = player.r * pp;
    var pg = ctx.createRadialGradient(player.x, player.y, 0, player.x, player.y, pr * 3);
    pg.addColorStop(0, rgba(pc, 0.5)); pg.addColorStop(0.5, rgba(pc, 0.12)); pg.addColorStop(1, rgba(pc, 0));
    ctx.fillStyle = pg; ctx.beginPath(); ctx.arc(player.x, player.y, pr * 3, 0, 6.28); ctx.fill();
    ctx.fillStyle = rgb(pc); ctx.beginPath(); ctx.arc(player.x, player.y, pr, 0, 6.28); ctx.fill();

    if (state === ACTIVE) {
      var bw = W * 0.28, bx = (W - bw) / 2, by = 14;
      ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fillRect(bx, by, bw, 4);
      var hf = health / 100;
      ctx.fillStyle = hf > 0.5 ? 'rgba(42,230,160,0.75)' : hf > 0.25 ? 'rgba(240,200,50,0.75)' : 'rgba(240,65,80,0.75)';
      ctx.fillRect(bx, by, bw * hf, 4);
      ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.font = '13px system-ui,sans-serif'; ctx.textAlign = 'right';
      ctx.fillText(score, W - 14, 20);
    }

    if (state === DORMANT) {
      var a = 0.35 + Math.sin(time * 1.5) * 0.15;
      ctx.fillStyle = 'rgba(255,255,255,' + a + ')'; ctx.font = '17px system-ui,sans-serif'; ctx.textAlign = 'center';
      ctx.fillText('touch to awaken', W / 2, H / 2 + 50);
    }

    if (state === OVER) {
      ctx.fillStyle = 'rgba(8,8,32,0.55)'; ctx.fillRect(0, 0, W, H);
      ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(255,255,255,0.75)'; ctx.font = '22px system-ui,sans-serif'; ctx.fillText('dissolved', W / 2, H / 2 - 8);
      ctx.fillStyle = 'rgba(255,255,255,0.45)'; ctx.font = '15px system-ui,sans-serif'; ctx.fillText('collected ' + score, W / 2, H / 2 + 20);
      var a2 = 0.3 + Math.sin(time * 1.5) * 0.12;
      ctx.fillStyle = 'rgba(255,255,255,' + a2 + ')'; ctx.font = '14px system-ui,sans-serif'; ctx.fillText('touch to reawaken', W / 2, H / 2 + 48);
    }

    animId = requestAnimationFrame(loop);
  }

  var stop = init();
  document.addEventListener('nav', function () { if (stop) stop(); stop = init(); });
}();
