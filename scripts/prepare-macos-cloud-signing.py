#!/usr/bin/env python3
"""Generate a local Xcode signing host to obtain the Mac CloudKit provisioning profile."""
import argparse
import pathlib
import plistlib
parser = argparse.ArgumentParser()
parser.add_argument('--extra-container')
args = parser.parse_args()
containers = ['iCloud.network.utterleaf.personal']
if args.extra_container:
    if not args.extra_container.startswith('iCloud.network.utterleaf.'):
        parser.error('The control container must belong to the UtterLeaf namespace.')
    containers.append(args.extra_container)
root = pathlib.Path(__file__).resolve().parents[1] / '.local/macos-cloud-signing'
project = root / 'SigningHost.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
(root / 'Probe.swift').write_text('import Cocoa\n@main struct SigningHost { static func main() {} }\n')
plistlib.dump({'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
              'CFBundleName':'CloudSigningHost','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1',
              'LSMinimumSystemVersion':'14.0'}, (root/'Info.plist').open('wb'))
plistlib.dump({'com.apple.security.device.audio-input':True,
              'com.apple.developer.icloud-services':['CloudKit'],
              'com.apple.developer.icloud-container-identifiers':containers,
              'com.apple.developer.icloud-container-environment':'Development'},(root/'Cloud.entitlements').open('wb'))
ids = {key: f'{index:024X}' for index,key in enumerate(['project','group','products','target','product','source','build','sources','projectConfigs','targetConfigs','projectRelease','targetRelease'],1)}
obj = {}
obj[ids['project']]={'isa':'PBXProject','attributes':{'LastUpgradeCheck':'2640','TargetAttributes':{ids['target']:{'ProvisioningStyle':'Automatic','SystemCapabilities':{'com.apple.iCloud':{'enabled':1}}}}},'buildConfigurationList':ids['projectConfigs'],'compatibilityVersion':'Xcode 14.0','developmentRegion':'en','knownRegions':['en','Base'],'mainGroup':ids['group'],'productRefGroup':ids['products'],'projectDirPath':'','projectRoot':'','targets':[ids['target']]}
obj[ids['group']]={'isa':'PBXGroup','children':[ids['source'],ids['products']],'sourceTree':'<group>'}
obj[ids['products']]={'isa':'PBXGroup','children':[ids['product']],'name':'Products','sourceTree':'<group>'}
obj[ids['target']]={'isa':'PBXNativeTarget','buildConfigurationList':ids['targetConfigs'],'buildPhases':[ids['sources']],'buildRules':[],'dependencies':[],'name':'SigningHost','productName':'CloudSigningHost','productReference':ids['product'],'productType':'com.apple.product-type.application'}
obj[ids['product']]={'isa':'PBXFileReference','explicitFileType':'wrapper.application','path':'CloudSigningHost.app','sourceTree':'BUILT_PRODUCTS_DIR'}
obj[ids['source']]={'isa':'PBXFileReference','lastKnownFileType':'sourcecode.swift','path':'Probe.swift','sourceTree':'<group>'}
obj[ids['build']]={'isa':'PBXBuildFile','fileRef':ids['source']}
obj[ids['sources']]={'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':[ids['build']],'runOnlyForDeploymentPostprocessing':'0'}
for scope in ['project','target']:
 obj[ids[scope+'Configs']]={'isa':'XCConfigurationList','buildConfigurations':[ids[scope+'Release']],'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'}
 obj[ids[scope+'Release']]={'isa':'XCBuildConfiguration','name':'Release','buildSettings':{}}
obj[ids['projectRelease']]['buildSettings']={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0'}
obj[ids['targetRelease']]['buildSettings']={'PRODUCT_NAME':'CloudSigningHost','PRODUCT_BUNDLE_IDENTIFIER':'network.utterleaf.personal','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'2LRMHSV528','INFOPLIST_FILE':'Info.plist','CODE_SIGN_ENTITLEMENTS':'Cloud.entitlements','ENABLE_HARDENED_RUNTIME':'YES','COMBINE_HIDPI_IMAGES':'YES'}
plistlib.dump({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':obj,'rootObject':ids['project']},(project/'project.pbxproj').open('wb'),sort_keys=False)
print('Prepared local macOS CloudKit signing host.')
