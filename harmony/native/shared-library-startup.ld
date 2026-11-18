/* The pinned OHOS fork adds executable Scrt1.o even for sharedLib.
 * Remove only that startup object, not Kotlin initializers or crti/crtn.
 * This avoids importing a fake main into an independently loadable SDK.
 */
SECTIONS {
    /DISCARD/ : { *Scrt1.o(*) }
}
INSERT AFTER .text;
