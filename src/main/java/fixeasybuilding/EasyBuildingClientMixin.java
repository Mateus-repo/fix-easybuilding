package fixeasybuilding;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import net.minecraft.client.Minecraft;

@Mixin(targets = "marum.easybuilding.EasyBuildingClient")
public class EasyBuildingClientMixin {
    @Inject(method = "onClientTick(Lnet/neoforged/neoforge/client/event/ClientTickEvent$Post;)V", at = @At("HEAD"), cancellable = true, remap = false)
    private static void onClientTick(CallbackInfo ci) {
        if (Minecraft.getInstance().player == null) {
            ci.cancel();
        }
    }
}
