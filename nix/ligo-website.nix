{ buildNpmPackage, writeShellScriptBin, yarn, linkFarm, nodejs-slim, python2
, ligo-changelog, ligo-doc, ligo-deb, ligo-static }:
buildNpmPackage {
  src = ../gitlab-pages/website;
  npmBuild = "npm run build";
  preBuild = ''
    cp -r ${../gitlab-pages/docs} $NIX_BUILD_TOP/docs
    chmod 700 -R $NIX_BUILD_TOP/docs
    cp -f ${ligo-changelog}/changelog.md $NIX_BUILD_TOP/docs/intro/changelog.md
  '';
  installPhase = ''
    cp -Lr build $out
    cp -r ${ligo-deb}/ligo.deb $out/deb
    mkdir -p $out/bin/linux
    cp -r ${ligo-static}/bin/ligo $out/bin/linux/ligo
    cp -r ${ligo-doc}/share/doc $out/odoc
  '';
  extraEnvVars.nativeBuildInputs = [ python2 ];
}
