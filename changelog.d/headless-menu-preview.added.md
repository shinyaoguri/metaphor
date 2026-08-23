- The headless status item's menu now shows a live thumbnail of the frame being
  rendered, so an offscreen run tells you *what* it is drawing and not just that
  it is alive. The frame is downscaled on the GPU and read back only while the
  menu is open (plus once at startup, so a `noLoop()` sketch still has a picture
  to show) — a closed menu costs one boolean check per frame. The numbers next
  to it (measured fps, frame count, elapsed) refresh while the menu stays open.
