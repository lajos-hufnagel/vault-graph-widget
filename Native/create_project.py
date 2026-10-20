"""Erzeugt das Xcode-Projekt ohne Zusatzwerkzeuge."""
from pathlib import Path
import hashlib, json, plistlib
root=Path(__file__).parent
objects={}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(object_key,isa,**fields):
 key=ident(object_key);objects[key]={'isa':isa,**fields};return key
refs={}
for filename in ['App.swift','Graph.swift','Widget.swift','App.entitlements','Widget.entitlements','App-Info.plist','Widget-Info.plist','AppIcon.icns','VaultGraphIcon.png','Assets.xcassets']:
 refs[filename]=add(filename,'PBXFileReference',lastKnownFileType='sourcecode.swift' if filename.endswith('.swift') else ('folder.assetcatalog' if filename.endswith('.xcassets') else 'image.png' if filename.endswith('.png') else 'image.icns' if filename.endswith('.icns') else 'text.plist.xml'),path=filename,sourceTree='<group>')
app_product=add('appProduct','PBXFileReference',explicitFileType='wrapper.application',path='VaultGraph.app',sourceTree='BUILT_PRODUCTS_DIR')
widget_product=add('widgetProduct','PBXFileReference',explicitFileType='wrapper.app-extension',path='VaultGraphWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[app_product,widget_product],name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=list(refs.values())+[products],sourceTree='<group>')
def configurations(name,base):
 ids=[]
 for kind in ['Debug','Release']:
  settings=dict(base,SWIFT_OPTIMIZATION_LEVEL='-Onone' if kind=='Debug' else '-O')
  ids.append(add(name+kind,'XCBuildConfiguration',name=kind,buildSettings=settings))
 return add(name+'Configurations','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
base={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CODE_SIGN_STYLE':'Automatic','ENABLE_APP_SANDBOX':'YES','MARKETING_VERSION':'0.1','CURRENT_PROJECT_VERSION':'1','CLANG_ENABLE_MODULES':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'}
project_configs=configurations('project',base)
def target(name,files,product,bundle,entitlements,info,extension=False):
 builds=[add(name+f,'PBXBuildFile',fileRef=refs[f]) for f in files]
 source=add(name+'Sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=builds,runOnlyForDeploymentPostprocessing='0')
 frameworks=add(name+'Frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
 settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':bundle,'CODE_SIGN_ENTITLEMENTS':entitlements,'INFOPLIST_FILE':info,'GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks']}
 if extension: settings.update(SKIP_INSTALL='YES',APPLICATION_EXTENSION_API_ONLY='YES')
 return add(name,'PBXNativeTarget',name=name,productName=name,productReference=product,productType='com.apple.product-type.app-extension' if extension else 'com.apple.product-type.application',buildConfigurationList=configurations(name,settings),buildPhases=[source,frameworks],buildRules=[],dependencies=[])
widget=target('VaultGraphWidget',['Widget.swift','Graph.swift'],widget_product,'de.lajoshufnagel.VaultGraph.Local.Widget','Widget.entitlements','Widget-Info.plist',True)
app=target('VaultGraph',['App.swift','Graph.swift'],app_product,'de.lajoshufnagel.VaultGraph.Local','App.entitlements','App-Info.plist')
iconbuild=add('VaultGraphAppIcon.icns','PBXBuildFile',fileRef=refs['AppIcon.icns'])
resources=add('VaultGraphResources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[iconbuild],runOnlyForDeploymentPostprocessing='0')
objects[app]['buildPhases'].append(resources)
widgeticon=add('VaultGraphWidgetAppIcon.icns','PBXBuildFile',fileRef=refs['AppIcon.icns'])
widgetresources=add('VaultGraphWidgetResources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[widgeticon],runOnlyForDeploymentPostprocessing='0')
objects[widget]['buildPhases'].append(widgetresources)
for target_name,phase in [('VaultGraph',resources),('VaultGraphWidget',widgetresources)]:
 assetbuild=add(target_name+'Assets','PBXBuildFile',fileRef=refs['Assets.xcassets'])
 objects[phase]['files'].append(assetbuild)
 pngbuild=add(target_name+'IconPNG','PBXBuildFile',fileRef=refs['VaultGraphIcon.png'])
 objects[phase]['files'].append(pngbuild)
proxy=add('proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType='1',remoteGlobalIDString=widget,remoteInfo='VaultGraphWidget')
dep=add('dependency','PBXTargetDependency',target=widget,targetProxy=proxy)
embedfile=add('embedfile','PBXBuildFile',fileRef=widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed=add('embed','PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='',dstSubfolderSpec='13',files=[embedfile],name='Embed App Extensions',runOnlyForDeploymentPostprocessing='0')
objects[app]['dependencies']=[dep];objects[app]['buildPhases'].append(embed)
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2600','TargetAttributes':{app:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':'1'}}},widget:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':'1'}}}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='de',hasScannedForEncodings='0',knownRegions=['de','en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,widget])
def encode(value,indent=0):
 if isinstance(value,dict):return '{\n'+''.join('\t'*(indent+1)+json.dumps(str(k))+' = '+encode(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
 if isinstance(value,list):return '('+', '.join(encode(v,indent) for v in value)+')'
 return json.dumps(str(value))
folder=root/'VaultGraph.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
common={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName':'$(PRODUCT_NAME)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)','CFBundleIconFiles':['VaultGraphIcon.png'],'CFBundleIcons':{'CFBundlePrimaryIcon':{'CFBundleIconName':'AppIcon','CFBundleIconFiles':['VaultGraphIcon.png']}}}
for name,extra in [('App',{'CFBundlePackageType':'APPL','CFBundleDisplayName':'Vault Graph','CFBundleIconFile':'AppIcon.icns','CFBundleIconName':'AppIcon','NSPrincipalClass':'NSApplication','CFBundleURLTypes':[{'CFBundleURLName':'Vault Graph','CFBundleURLSchemes':['vaultgraph']}]}),('Widget',{'CFBundleDisplayName':'Vault Graph','CFBundleIconFile':'AppIcon.icns','CFBundleIconName':'AppIcon','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}})]:
 (root/(name+'-Info.plist')).write_bytes(plistlib.dumps(dict(common,**extra)))
print(folder)
