# Cube Pong

A six-face 3D Pong prototype built with Godot 4.7 and GDScript.

## Run it

1. Open this folder as a Godot project and run the Arena (`F6` while `arena.tscn` is open, or `F5` for the main scene).
2. Select **Local test (WASD + bots)** to play one paddle against five bots. The default test face is `Paddle_PosZ`; change `offline_test_paddle_name` on the paddle script if you want a different face.
3. For LAN, one computer selects **Host LAN game** and the others select **Find a host on this LAN**. The host can start the match from the lobby. `F1` and `F2` are keyboard shortcuts for host and discovery.
4. During a match, WASD moves the assigned paddle. Move the mouse to look around; horizontal look is limited to 180 degrees. Press `Esc` to release the mouse and click the game window to capture it again.

The lobby lists each player's IPv4 address and assigned face. Empty faces are controlled by bots. Each face starts with three lives. A ball entering a face's scoring area removes one life; the next serve starts a faster round. The match lasts three minutes, and the player with the most lives wins when time expires.

For LAN play, both peers need to be on the same local network, and UDP ports 8910 (game) and 8911 (host discovery) must be allowed by the computers' firewalls.
