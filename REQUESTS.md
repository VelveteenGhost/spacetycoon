# Requests for Eli

Newest first. Each item says what, why and by when. I keep working on anything that doesn't depend on you.
Items marked **BLOCKING** stop a whole phase.

## 2026-11-09: everything still needed to finish the port

**Now**

1. **Publish the place when you want the phone build: File > Publish to Roblox in Studio.** You OK'd me publishing,
   but I can't: Open Cloud publishes only from a place file, and MCP has no way to save one out of Studio. Every
   change lives in the Team Create session, so a publish from your Studio picks up all of it. I'll say in each
   update whether there's anything new worth publishing.

**At the phone test (after lighting and effects on the near cameras)**

2. **About 15 minutes with the private game on your phone at its default graphics.** Tell me the phone model.
   This is the go/no-go from Nov 8:
   - Does the static fire on the mount and pad cameras read as the same place, light and vehicle as the mood
     study?
   - Does it stay smooth?
   - Does the press-site shot hold up?
   - Do the flame and glows speckle? The Studio emulator missed that problem in the mood study.
3. **The look sign-off, beside the mood study.** That call is yours. The deck has the six looks (blue hour,
   sunrise, morning × clear, broken, marine); blue hour and marine had the least tuning.

**Whenever**

4. **Merge PR #2 into `main`,** and tell me whether to push `studio-port` and open a PR for it.

## Answered Nov 9

- ~~Set Lighting.Technology to Future~~: you set the new LightingStyle to Realistic instead; lighting is built on it.
- ~~OK to upload effect textures~~: approved; 11 effect images and the sky faces are up (ASSETS.md).
- ~~Who publishes~~: you OK'd me, but I can't from MCP (item 1).

## 2026-11-08 (done)

- ~~Split 13 meshes by material~~: PR #2 is merged into `studio-port`, VEH revision 2 is in, and SITE is uploaded.
- ~~Approve the upload folder~~ and ~~OK to create permanent assets~~: VEH, PAD, TWR and SITE are uploaded.
