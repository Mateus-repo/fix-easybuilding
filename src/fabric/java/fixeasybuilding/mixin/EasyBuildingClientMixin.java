package fixeasybuilding.mixin;

import marum.easybuilding.client.PlaneMode;
import net.minecraft.client.Minecraft;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Easy Building keeps the whole "plane mode" state in static fields
 * ({@code marum.easybuilding.client.PlaneMode}). When the client leaves a world
 * (disconnect, "Save and Quit to Title", return to the main menu) {@code Minecraft.player}
 * becomes {@code null} while {@code PlaneMode.active} stays {@code true}. The mod's
 * end-of-tick handler then dereferences the player and the game dies with a
 * NullPointerException.
 *
 * <p>This mixin runs at the very start of every client tick, before any loader tick
 * handler, and wipes the leftover state whenever there is no player. It is deliberately
 * anchored on Minecraft instead of on Easy Building internals, so it keeps working no
 * matter how the mod registers its tick handler (NeoForge event, Fabric lambda, ...).
 */
@Mixin(Minecraft.class)
public class EasyBuildingClientMixin {

    @Inject(method = "tick()V", at = @At("HEAD"), require = 0, remap = false)
    private void fixeasybuilding$clearStalePlaneMode(CallbackInfo ci) {
        Minecraft minecraft = (Minecraft) (Object) this;

        if (minecraft.player == null && PlaneMode.active) {
            PlaneMode.clear();
        }
    }
}
