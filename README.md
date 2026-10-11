# Cube Pong

A six-face 3D Pong survival game built with Godot 4.7 and GDScript. The current build is single-player: you control one face and compete against five bots. Each cube face and paddle has its own Rubik's Cube color: red, orange, blue, green, white, or yellow.

## Start playing

1. Open this folder in Godot and press **F5** (or run `scenes/arena.tscn` with **F6**).
2. Choose your face and bot difficulty, then click **Play against 5 bots**. Faces use a consistent color and axis key: front +Z red, back −Z orange, right +X blue, left −X green, top +Y white, and bottom −Y yellow.
3. Move with **WASD** relative to your chosen face. Move or flick the mouse horizontally or vertically at the same time to tilt the paddle and steer the ball on a hit; the paddle gradually springs back to neutral. Hold **Shift while moving** to spend boost fuel for a 1.4× paddle speed increase. The meter recharges when you are not boosting. Your paddle is slightly transparent so you can see the ball through it. Each round begins with a centered 3-second countdown. The face cameras are centered and use a wider 95-degree field of view. The camera smoothly tracks the ball, with a small pan as it moves. Press **Esc** to release the mouse.

## How to win

Each face has three lives. A colored crater pulse marks the face where the ball scores. Faces with more lives return the ball slightly softer; faces on their last life return it slightly faster. Keep your paddle between the ball and your face's scoring area. If the ball passes your paddle, your face loses a life. The ball serves again faster after each lost life. Eliminate all five bots to win, or survive until the three-minute timer ends with the most lives. If you lose all three lives, the game slows exponentially while the screen fades into the defeat screen.

**Relaxed**, **Classic**, and **Fierce** adjust bot aim, reaction time, speed, and chance of making a bad intercept read (20%, 10%, and 4% per incoming shot, respectively). Choose a different face and difficulty from the menu after a match to play again.
