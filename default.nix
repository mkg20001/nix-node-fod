{ nodejs_latest
, yarn
, git
, lib
, ...
}:

{ depsSha256 ? null, depsHash ? null # hash of dependency
, node ? nodejs_latest # node version to use
, useYarn ? false # use yarn instead of npm
, forceRebuild ? true # always rebuild downloaded binaries instead of pulling them

, meta ? {}, pname, version, src, installPhase ? null, nativeBuildInputs ? [], buildInputs ? []
, ... }@attrs:

let
  cleanAttrs = builtins.removeAttrs attrs ["depsSha256" "depsHash" "node" "useYarn" "forceRebuild"];

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

  node_modules = stdenvNoCC.mkDerivation(extraBuild // {
    inherit meta pname version src;

    nativeBuildInputs = [ node git ]
      ++ (lib.optionals useYarn [ yarn ]);

    buildPhase = if useYarn then ''
      HOME=/tmp yarn install --frozen-lockfile
    '' else ''
      HOME=/tmp npm ci
    '';

    installPhase = ''
      cp -rp node_modules $out
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
    ++ [ git ];

  buildInputs = buildInputs
    ++ [ node ];

  nodeModCopy = ''
    cp -rp ${node_modules} node_modules
  '';

  nodeInstall = ''
    tarball=$(npm pack | tail -n 1)
    tar xfz "$tarball"
    mkdir -p "$out"
    cp -a package/. "$out"

    cp -rp ${node_modules} $out/node_modules

    mkdir -p $out/bin
    # TODO: will possibly break if .bin is literal string (in which case we need to map it to {key: .name, value: .bin})
    cat "$out/package.json" | jq -r --arg out "$out" 'select(.bin != null) | .bin | to_entries | .[] | ["ln", "-s", $out + "/" + .value, $out + "/bin/" + .key] | join(" ")' | sh -ex -
  '';

  installPhase = if (installPhase != null) then installPhase else''
    runHook nodeInstall
  '';
})
