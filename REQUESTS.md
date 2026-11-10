# Requests for Eli

Newest first. Each item says what, why and by when. I keep working on anything that doesn't depend on you.
Items marked **BLOCKING** stop a whole phase.

## 2026-11-09: everything still needed to finish the port

**Now**

1. **Publish the place when you want the phone build: File > Publish to Roblox in Studio.** You OK'd me publishing,
   but I can't (rechecked after your playtest). Open Cloud publishes only from a place file sent as the request
   body, which the MCP tool can't send. Studio has no save or publish call I can reach, and the input tool only
   talks to the running game. Every change lives in the Team Create session, so a publish from your Studio picks up
   all of it. New since your playtest: the separation jitter fix, the longer contrail and the camera buttons.
2. **Optional: connect Rojo to sync code from the repo.** In Studio, open the Rojo plugin (install it from the
   Creator Store, or I can run `rojo plugin install`), then run `rojo serve` in the repo and click Connect. Edits
   to `src/` then reach Studio as they're saved, for both of us. The project maps only the code and never deletes,
   so the scene is safe. The scene itself (meshes, terrain, lighting) lives in Studio and Team Create, not the repo.
   The first sync adds `Port.Manifest`, the export manifest as a module, which Studio doesn't have yet; nothing
   requires it.

**At the phone test (ready now: lighting, effects and the altitude set are in)**

3. **About 15 minutes with the private game on your phone at its default graphics.** Tell me the phone model.
   This is the go/no-go from Nov 8:
   - Does the static fire on the mount and pad cameras read as the same place, light and vehicle as the mood
     study?
   - Does it stay smooth, especially at liftoff with the ground cloud at its fullest, and inside the cloud on the
     mount and pad cameras around T+10 to T+20?
   - Does the press-site shot hold up?
   - Do the flame and glows speckle? The Studio emulator missed that problem in the mood study.
   - Motion is the one thing I can't judge: unfocused Studio draws about two frames a second. Watch the flame, the
     cloud's spread and the camera moves.
4. **The look sign-off, beside the mood study.** That call is yours. Start with
   `previews/port/launch_T+20_sheet.jpg`, which has every camera at T+20 next to the mood study's frame. It's on
   this machine only, since `previews/` isn't in git. PLAN phase 8 lists what I already see as off: the far skies
   are too tan and the tracker's ground goes black. The six looks are blue hour, sunrise and morning × clear,
   broken and marine; blue hour, morning and marine had the least tuning.

**Whenever**

5. **Push `studio-port` to GitHub, or let me.** It's ready, but my push was blocked by this session's permission
   check. Run `git push -u origin studio-port`, or allow the push and I'll do it. It's 15 commits ahead of `main`,
   and `main`'s only extra commit is your merge of PR #2, whose content the branch already has, so a PR into
   `main` would merge cleanly whenever you want one.

## Answered Nov 9

- ~~Set Lighting.Technology to Future~~: you set the new LightingStyle to Realistic instead; lighting is built on it.
- ~~OK to upload effect textures~~: approved; 11 effect images and the sky faces are up (ASSETS.md).
- ~~Who publishes~~: you OK'd me, but I can't from MCP (item 1).

## 2026-11-08 (done)

- ~~Split 13 meshes by material~~: PR #2 is merged into `studio-port`, VEH revision 2 is in, and SITE is uploaded.
- ~~Approve the upload folder~~ and ~~OK to create permanent assets~~: VEH, PAD, TWR and SITE are uploaded.
