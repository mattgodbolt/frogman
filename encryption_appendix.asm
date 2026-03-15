; ============================================================================
; FROGMAN — Original Loader Encryption (Historical Reference)
; ============================================================================
; This file documents the original encryption scheme used by the Loader
; file (&2800-&47FF, 8KB). It is NOT part of the build — it exists purely
; as historical documentation of the copy protection.
;
; The Loader implements a ~55-stage XOR decryption chain. Each stage:
;   1. XOR 5 single bytes with fixed keys (&BA, &19, &C3, &04)
;   2. XOR a 256-byte block with key &7D
;   3. XOR with VIA Timer 1 value (&FE64/&FE65) — timing-dependent!
;   4. XOR with a second VIA timer read (different seed)
;   5. XOR each byte with its index (0-255)
;   6. Wait for disk I/O completion (&0355 == 7)
;   7. Restore NMI vector (&FFFC/&FFFD → &0202/&0203)
;   8. Advance to next decryption stage
;
; The VIA timer dependency makes static analysis impossible — the XOR
; keys change based on exact CPU cycle timing, which varies with disk
; motor speed, head seek time, and interrupt latency. Even single-stepping
; in a debugger produces different decryption results.
;
; As the original ReadMe proudly states:
;   "The program uses a unique coding system which makes the code
;    nearly unhackable"
;
; The decryption chain starts at &290B in the Loader file.
; After all stages complete, the Loader has:
;   - Loaded and decrypted FastIO → &0700 (engine + tables)
;   - Loaded and decrypted level data → appropriate addresses
;   - Loaded and decrypted graphics → &3700, &4800, &7800
;   - Set up the IRQ vector to point to &0600
;   - Jumped to game initialization
;
; The Loader's own memory (&2800-&47FF) is then overwritten by level
; map data, destroying the decryption code after it has served its purpose.
; ============================================================================
