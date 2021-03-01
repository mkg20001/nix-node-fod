{
  description = "Node packaging module that downloads dependencies using a FOD";

  outputs = { self }: {

    lib.nix-node-fod = import ./.;

  };
}
