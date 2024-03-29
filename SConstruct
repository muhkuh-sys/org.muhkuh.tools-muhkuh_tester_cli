# -*- coding: utf-8 -*-
#-------------------------------------------------------------------------#
#   Copyright (C) 2014 by Christoph Thelen                                #
#   doc_bacardi@users.sourceforge.net                                     #
#                                                                         #
#   This program is free software; you can redistribute it and/or modify  #
#   it under the terms of the GNU General Public License as published by  #
#   the Free Software Foundation; either version 2 of the License, or     #
#   (at your option) any later version.                                   #
#                                                                         #
#   This program is distributed in the hope that it will be useful,       #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#   GNU General Public License for more details.                          #
#                                                                         #
#   You should have received a copy of the GNU General Public License     #
#   along with this program; if not, write to the                         #
#   Free Software Foundation, Inc.,                                       #
#   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             #
#-------------------------------------------------------------------------#


#----------------------------------------------------------------------------
#
# Set up the Muhkuh Build System.
#

SConscript('mbs/SConscript')
Import('atEnv')

import os.path


#----------------------------------------------------------------------------
#
# Add the version numbers to the tester script.
#
tTestSystemLua = atEnv.DEFAULT.Version('#targets/lua/test_system.lua', 'local/lua/test_system.lua')


#----------------------------------------------------------------------------
#
# Build the artifacts.
#
strGroup = 'org.muhkuh.tools'
strModule = 'muhkuh_tester_cli'

# Split the group by dots.
aGroup = strGroup.split('.')
# Build the path for all artifacts.
strModulePath = 'targets/jonchki/repository/%s/%s/%s' % ('/'.join(aGroup), strModule, PROJECT_VERSION)

# Set the name of the artifact.
strArtifact0 = 'lua5.1-muhkuh_tester_cli'

tArcList0 = atEnv.DEFAULT.ArchiveList('zip')

tArcList0.AddFiles('',
	'installer/jonchki/install.lua',
	'local/system.lua')

tArcList0.AddFiles('doc/org.muhkuh.tools-muhkuh_tester_cli/',
	'doc/org.muhkuh.tools-muhkuh_tester_cli/main.asciidoc')

tArcList0.AddFiles('lua/',
	tTestSystemLua)

tArcList0.AddFiles('wrapper/linux/',
	'local/wrapper/lua5.1/linux/tester')

tArcList0.AddFiles('wrapper/windows/',
	'local/wrapper/lua5.1/windows/tester.bat')

tArtifact0 = atEnv.DEFAULT.Archive(os.path.join(strModulePath, '%s-%s.zip' % (strArtifact0, PROJECT_VERSION)), None, ARCHIVE_CONTENTS = tArcList0)
tArtifact0Hash = atEnv.DEFAULT.Hash('%s.hash' % tArtifact0[0].get_path(), tArtifact0[0].get_path(), HASH_ALGORITHM='md5,sha1,sha224,sha256,sha384,sha512', HASH_TEMPLATE='${ID_UC}:${HASH}\n')
tConfiguration0 = atEnv.DEFAULT.Version(os.path.join(strModulePath, '%s-%s.xml' % (strArtifact0, PROJECT_VERSION)), 'installer/jonchki/lua5.1/%s.xml' % strModule)
tConfiguration0Hash = atEnv.DEFAULT.Hash('%s.hash' % tConfiguration0[0].get_path(), tConfiguration0[0].get_path(), HASH_ALGORITHM='md5,sha1,sha224,sha256,sha384,sha512', HASH_TEMPLATE='${ID_UC}:${HASH}\n')
tArtifact0Pom = atEnv.DEFAULT.ArtifactVersion(os.path.join(strModulePath, '%s-%s.pom' % (strArtifact0, PROJECT_VERSION)), 'installer/jonchki/lua5.1/pom.xml')


# Set the name of the artifact.
strArtifact1 = 'lua5.4-muhkuh_tester_cli'

tArcList1 = atEnv.DEFAULT.ArchiveList('zip')

tArcList1.AddFiles('',
	'installer/jonchki/install.lua',
	'local/system.lua')

tArcList1.AddFiles('doc/org.muhkuh.tools-muhkuh_tester_cli/',
	'doc/org.muhkuh.tools-muhkuh_tester_cli/main.asciidoc')

tArcList1.AddFiles('lua/',
	tTestSystemLua)

tArcList1.AddFiles('wrapper/linux/',
	'local/wrapper/lua5.4/linux/tester')

tArcList1.AddFiles('wrapper/windows/',
	'local/wrapper/lua5.4/windows/tester.bat')

tArtifact1 = atEnv.DEFAULT.Archive(os.path.join(strModulePath, '%s-%s.zip' % (strArtifact1, PROJECT_VERSION)), None, ARCHIVE_CONTENTS = tArcList1)
tArtifact1Hash = atEnv.DEFAULT.Hash('%s.hash' % tArtifact1[0].get_path(), tArtifact1[0].get_path(), HASH_ALGORITHM='md5,sha1,sha224,sha256,sha384,sha512', HASH_TEMPLATE='${ID_UC}:${HASH}\n')
tConfiguration1 = atEnv.DEFAULT.Version(os.path.join(strModulePath, '%s-%s.xml' % (strArtifact1, PROJECT_VERSION)), 'installer/jonchki/lua5.4/%s.xml' % strModule)
tConfiguration1Hash = atEnv.DEFAULT.Hash('%s.hash' % tConfiguration1[0].get_path(), tConfiguration1[0].get_path(), HASH_ALGORITHM='md5,sha1,sha224,sha256,sha384,sha512', HASH_TEMPLATE='${ID_UC}:${HASH}\n')
tArtifact1Pom = atEnv.DEFAULT.ArtifactVersion(os.path.join(strModulePath, '%s-%s.pom' % (strArtifact1, PROJECT_VERSION)), 'installer/jonchki/lua5.4/pom.xml')
