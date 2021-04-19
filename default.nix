{ nodejs_latest
, yarn
, git
, jq
, lib
, cacert
, stdenv
, stdenvNoCC
, ...
}:

{ depsSha256 ? null, depsHash ? "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # hash of dependency
, node ? nodejs_latest # node version to use
, useYarn ? false # use yarn instead of npm
, forceRebuild ? true # always rebuild downloaded binaries instead of pulling them
, depsAttrs ? {} # extra attributes for fetchderivation
# TODO: fetch deps for install with --production and add option for it
# TODO: add option for non-install deps and set it to default true
# TODO: support multipackage repos, by doing a find for -name node_modules -type d and adding that to tar

, meta ? {}, pname, version, src, installPhase ? null, nativeBuildInputs ? [], buildInputs ? []
, ... }@attrs:

let
  cleanAttrs = builtins.removeAttrs attrs ["depsSha256" "depsHash" "node" "useYarn" "forceRebuild" "depsAttrs"];

  extraBuild = {
    prePhases = [ "nodeExports" "nodeGypHeaders" ];

    nodeExports = ''
      # fix update check failed errors
      export NO_UPDATE_NOTIFIER=true
    '';

    nodeGypHeaders = ''
      NODE_VERSION=$(node --version | sed "s|v||g")
      GYP_FOLDER="/tmp/.cache/node-gyp/$NODE_VERSION"
      mkdir -p "$GYP_FOLDER"
      ln -s ${node}/include "$GYP_FOLDER/include"
      echo 9 > "$GYP_FOLDER/installVersion"
    '';
  };

  node_modules = stdenvNoCC.mkDerivation(extraBuild // depsAttrs // {
    inherit meta src;

    name = "node-deps-${pname}.tar.gz";

    nativeBuildInputs = [ node git cacert ]
      ++ (lib.optionals useYarn [ yarn ]);

    buildPhase = if useYarn then ''
      HOME=/tmp yarn install --frozen-lockfile
    '' else ''
      HOME=/tmp npm ci
    '';

    installPhase = ''
      runHook preInstall
      rm -rf $out

      GZIP=-9n tar --sort=name \
            --mtime="@''${SOURCE_DATE_EPOCH}" \
            --owner=0 --group=0 --numeric-owner \
            --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
            cfzp $out $(find -type d -name node_modules)

      runHook postInstall
    '';

    outputHashAlgo = if (depsSha256 != null) then "sha256" else null;
    outputHashMode = "recursive";
    outputHash = if (depsSha256 != null) then depsSha256 else depsHash;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars;
  });
in

stdenv.mkDerivation (extraBuild // cleanAttrs // {
  preBuildPhases = [ "nodeModCopy" ];

  nativeBuildInputs = nativeBuildInputs
    ++ (lib.optionals useYarn [ yarn ])
    ++ [ git node jq ];

  buildInputs = buildInputs
    ++ [ node ];

  nodeModCopy = ''
    tar xfz ${node_modules}
    patchShebangs $(find -type d -name node_modules)
  '';

  nodeInstall = ''
    tarball=$(npm pack | tail -n 1)
    tar xfz "$tarball"
    mkdir -p "$out"
    cp -a package/. "$out"

    tar xfz ${node_modules} -C $out

    mkdir -p $out/bin
    # TODO: will possibly break if .bin is literal string (in which case we need to map it to {key: .name, value: .bin})
    cat "$out/package.json" | jq -r --arg out "$out" 'select(.bin != null) | .bin | to_entries | .[] | ["ln", "-s", $out + "/" + .value, $out + "/bin/" + .key] | join(" ")' | sh -ex -
  '';

  installPhase = if (installPhase != null) then installPhase else ''
    runHook preInstall
    runHook nodeInstall
    runHook postInstall
  '';
})
