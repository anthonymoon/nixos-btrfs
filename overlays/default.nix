{
  inputs,
  outputs,
}: {
  # Add custom overlays here if needed
  # Example:
  # modifications = final: prev: {
  #   some-package = prev.some-package.overrideAttrs (oldAttrs: {
  #     patches = oldAttrs.patches ++ [ ./my-patch.patch ];
  #   });
  # };
}
