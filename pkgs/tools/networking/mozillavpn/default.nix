{ buildGoModule
, cmake
, fetchFromGitHub
, go
, lib
, libsecret
, pkg-config
, polkit
, python3
, qt5compat
, qtbase
, qtcharts
, qtnetworkauth
, qttools
, qtwebsockets
, rustPlatform
, stdenv
, wireguard-tools
, wrapQtAppsHook
}:

let
  pname = "mozillavpn";
  version = "2.13.0";
  src = fetchFromGitHub {
    owner = "mozilla-mobile";
    repo = "mozilla-vpn-client";
    rev = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-EwHuNJZpTb7oFOKKDv0zWgklUe95Th97KP9G5DqRokA=";
  };

  netfilter-go-modules = (buildGoModule {
    inherit pname version src;
    modRoot = "linux/netfilter";
    vendorHash = "sha256-Cmo0wnl0z5r1paaEf1MhCPbInWeoMhGjnxCxGh0cyO8=";
  }).go-modules;

  extensionBridgeDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}-extension-bridge";
    preBuild = "cd extension/bridge";
    hash = "sha256-q6Wf+jrGjGMiDEmnErnDau6Li64Dyq8t2SN1I4rspBY=";
  };
  signatureDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}-signature";
    preBuild = "cd signature";
    hash = "sha256-Dbu4WX2u3uDDUuZzS/hczypSFkQNnvuj2Su2X0QvSN4=";
  };
  vpngleanDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}-vpnglean";
    preBuild = "cd vpnglean";
    hash = "sha256-FDkziDDup+D7Bh+Wclqxn8Dhm/T2DanhjKXIAEFDhzc=";
  };

in
stdenv.mkDerivation {
  inherit pname version src;

  buildInputs = [
    libsecret
    polkit
    qt5compat
    qtbase
    qtcharts
    qtnetworkauth
    qtwebsockets
  ];
  nativeBuildInputs = [
    cmake
    go
    pkg-config
    python3
    python3.pkgs.glean-parser
    python3.pkgs.pyyaml
    python3.pkgs.setuptools
    rustPlatform.cargoSetupHook
    rustPlatform.rust.cargo
    rustPlatform.rust.rustc
    wrapQtAppsHook
  ];

  postUnpack = ''
    pushd source/extension/bridge
    cargoDeps='${extensionBridgeDeps}' cargoSetupPostUnpackHook
    extensionBridgeDepsCopy="$cargoDepsCopy"
    popd

    pushd source/signature
    cargoDeps='${signatureDeps}' cargoSetupPostUnpackHook
    signatureDepsCopy="$cargoDepsCopy"
    popd

    pushd source/vpnglean
    cargoDeps='${vpngleanDeps}' cargoSetupPostUnpackHook
    vpngleanDepsCopy="$cargoDepsCopy"
    popd
  '';
  dontCargoSetupPostUnpack = true;

  postPatch = ''
    substituteInPlace src/apps/vpn/platforms/linux/daemon/org.mozilla.vpn.dbus.service --replace /usr/bin/mozillavpn "$out/bin/mozillavpn"

    substituteInPlace scripts/addon/build.py \
      --replace 'qtbinpath = args.qtpath' 'qtbinpath = "${qttools.dev}/bin"' \
      --replace 'rcc = os.path.join(qtbinpath, rcc_bin)' 'rcc = "${qtbase.dev}/libexec/rcc"'

    substituteInPlace src/apps/vpn/cmake/linux.cmake \
      --replace '/etc/xdg/autostart' "$out/etc/xdg/autostart" \
      --replace '${"$"}{POLKIT_POLICY_DIR}' "$out/share/polkit-1/actions" \
      --replace '/usr/share/dbus-1' "$out/share/dbus-1" \
      --replace '${"$"}{SYSTEMD_UNIT_DIR}' "$out/lib/systemd/system"

    substituteInPlace extension/CMakeLists.txt \
      --replace '/etc' "$out/etc"

    ln -s '${netfilter-go-modules}' linux/netfilter/vendor

    pushd extension/bridge
    cargoDepsCopy="$extensionBridgeDepsCopy" cargoSetupPostPatchHook
    popd

    pushd signature
    cargoDepsCopy="$signatureDepsCopy" cargoSetupPostPatchHook
    popd

    pushd vpnglean
    cargoDepsCopy="$vpngleanDepsCopy" cargoSetupPostPatchHook
    popd

    cargoSetupPostPatchHook() { true; }
  '';

  cmakeFlags = [
    "-DQT_LCONVERT_EXECUTABLE=${qttools.dev}/bin/lconvert"
    "-DQT_LUPDATE_EXECUTABLE=${qttools.dev}/bin/lupdate"
    "-DQT_LRELEASE_EXECUTABLE=${qttools.dev}/bin/lrelease"
  ];
  dontFixCmake = true;

  qtWrapperArgs =
    [ "--prefix" "PATH" ":" (lib.makeBinPath [ wireguard-tools ]) ];

  meta = {
    description = "Client for the Mozilla VPN service";
    homepage = "https://vpn.mozilla.org/";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ andersk ];
    platforms = lib.platforms.linux;
  };
}
