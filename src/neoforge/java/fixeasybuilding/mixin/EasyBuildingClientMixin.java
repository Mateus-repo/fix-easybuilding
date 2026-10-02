package fixeasybuilding.mixin;

import marum.easybuilding.PlaneMode;
import net.minecraft.client.Minecraft;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Easy Building keeps the whole "plane mode" state in static fields
 * ({@code marum.easybuilding.PlaneMode}). When the client leaves a world (disconnect,
 * "Save and Quit to Title", return to the main menu) {@code Minecraft.player} becomes
 * {@code null} while {@code PlaneMode.active} stays {@code true}. The mod's
 * {@code ClientTickEvent.Post} handler then dereferences the player and the game dies
 * with a NullPointerException.
 *
 * <p>This mixin runs at the very start of every client tick, before NeoForge fires the
 * tick events, and wipes the leftover state whenever there is no player. It is
 * deliberately anchored on Minecraft instead of on the Easy Building tick handler, so it
 * keeps working across Easy Building and NeoForge versions.
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
