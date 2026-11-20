# Art direction

Short notes on Meltdown's own visual designs, so later work reuses them instead of
inventing again. Everything here is original (NAM-3): nothing is traced from, or
proportioned after, a ship, robot or level from the original Descent games.

## The player ship: "the kite" (#679)

First used as the ship marker on the held map (`game/xr/map_ship_marker.gd`). The same
silhouette is meant to become the M6 hull and the cockpit's outside shape.

- **Plan view (from above):** a swept delta, nose to tail about as long as it is wide
  (span about 0.76 of length). The nose is a single sharp point on the centre line. The
  rear edge is a swallowtail: the wing tips sit at the very back and the centre is
  notched forward by about a quarter of the length.
- **Side view:** almost flat. One tall dorsal fin on the centre line, rising from just
  behind mid-length to its top near the tail, about 0.3 of the length high. A shallow
  keel under the front half gives some depth seen edge-on.
- **Reading:** the fin is the only thing well above the wing plane, so the top side is
  never in doubt; the notch reads as "back" and the point as "front" at a glance.
- **Colour:** no fixed hull scheme yet. On the map it is the single marker colour from
  `game/xr/map_look.json` (orange). A hull scheme is chosen in M6.

Sketch (from above, nose up):

```
            ^
           / \
          /   \
         /  |  \      | = dorsal fin, on the centre line, aft
        /   |   \
       /   / \   \
      /___/   \___\
```
