// Public API of the 3D avatar system. Safe to import anywhere: nothing here loads three.js until a
// stage mounts or a portrait is first rendered.
//
//   <AvatarStage config interactive />            live drag-to-spin turntable (one per screen)
//   <AvatarPortrait config size view="portrait" /> cached still image (HUD, lists, chat, cards)
//   migrateAvatar(raw)                            any stored look (v1 2D or v2 3D) -> valid v2 look
//   AVATAR_OPTIONS, OUTFIT_PRESETS, applyPreset, randomAvatar, defaultAvatar   creator data
export * from './catalog';
export { AvatarPortrait, getAvatarImage, type AvatarPortraitProps, type PortraitView } from './AvatarPortrait';
export { AvatarStage, type AvatarStageProps } from './AvatarStage';
