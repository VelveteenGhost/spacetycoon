# Requests for Eli

Newest first. Each item says what, why and by when. I keep working on anything that doesn't depend on you.
Items marked **BLOCKING** stop a whole phase.

## 2026-11-09: everything still needed to finish the port

**Now**

1. **BLOCKING lighting: set Lighting.Technology to Future.** Select Lighting in the Explorer, then change
   Technology in Properties. It takes 30 seconds; MCP scripts can't write this property. Lighting is the next
   phase.
2. **OK to upload about 10 effect textures as images.** They're the billows, flame glow, plume streak, ice-shard
   flipbook, contrail, lamp glow and foam. They become permanent assets on your account, like the meshes, but
   images don't cost Robux. Needed for effects, the phase after lighting.
3. **Publishing: should I publish the place to the private game at each checkpoint, or will you?** Your phone
   only gets what's published. The game stays private; each publish is a new version in the place's history.
   Needed before the phone test.

**At the phone test (after lighting and effects on the near cameras)**

4. **About 15 minutes with the private game on your phone at its default graphics.** Tell me the phone model.
   This is the go/no-go from Nov 8:
   - Does the static fire on the mount and pad cameras read as the same place, light and vehicle as the mood
     study?
   - Does it stay smooth?
   - Does the press-site shot hold up?
   - Do the flame and glows speckle? The Studio emulator missed that problem in the mood study.
5. **The look sign-off, beside the mood study.** That call is yours.

**Whenever**

6. **Merge PR #2 into `main`,** and tell me whether to push `studio-port` and open a PR for it.

## 2026-11-08 (done)

- ~~Split 13 meshes by material~~: PR #2 is merged into `studio-port`, VEH revision 2 is in, and SITE is uploaded.
- ~~Approve the upload folder~~ and ~~OK to create permanent assets~~: VEH, PAD, TWR and SITE are uploaded.
