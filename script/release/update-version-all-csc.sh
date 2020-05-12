#!/bin/bash
set -e
# Update the version for for all droolsjbpm repositories

initializeWorkingDirAndScriptDir() {
    # Set working directory and remove all symbolic links
    workingDir=`pwd -P`

    # Go the script directory
    cd `dirname $0`
    # If the file itself is a symbolic link (ignoring parent directory links), then follow that link recursively
    # Note that scriptDir=`pwd -P` does not do that and cannot cope with a link directly to the file
    scriptFileBasename=`basename $0`
    while [ -L "$scriptFileBasename" ] ; do
        scriptFileBasename=`readlink $scriptFileBasename` # Follow the link
        cd `dirname $scriptFileBasename`
        scriptFileBasename=`basename $scriptFileBasename`
    done
    # Set script directory and remove other symbolic links (parent directory links)
    scriptDir=`pwd -P`
}


updateDroolsParentVersion() {
    '${mvnHome}/bin/mvn' -B -N versions:update-parent -Dfull\
     -DparentVersion=[$newDroolsVersion] -DallowSnapshots=true -DgenerateBackupPoms=false
}

updateDroolsChildModulesVersion() {
    '${mvnHome}/bin/mvn' -N -B versions:update-child-modules -Dfull\
     -DallowSnapshots=true -DgenerateBackupPoms=false
}

# Updates parent version and child modules versions for Maven project in current working dir
updateDroolsParentAndChildVersions() {
    updateDroolsParentVersion
    updateDroolsChildModulesVersion
}

updateUberfireParentVersion() {
    '${mvnHome}/bin/mvn' -B -N versions:update-parent -Dfull\
     -DparentVersion=[$newUberfireVersion] -DallowSnapshots=true -DgenerateBackupPoms=false
}

updateUberfireChildModulesVersion() {
    '${mvnHome}/bin/mvn' -N -B versions:update-child-modules -Dfull\
     -DallowSnapshots=true -DgenerateBackupPoms=false
}

# Updates parent version and child modules versions for Maven project in current working dir
updateUberfireParentAndChildVersions() {
    updateUberfireParentVersion
    updateUberfireChildModulesVersion
}

initializeWorkingDirAndScriptDir
droolsjbpmOrganizationDir="$scriptDir/../../.."

if [ $# != 1 ] && [ $# != 2 ]; then
    echo
    echo "Usage:"
    echo "  $0 newDroolsVersion newUberfireVersion"
    echo "For example:"
    echo "  $0 6.3.0.Final community"
    echo "  $0 6.3.1.20151105 productized"
    echo
    exit 1
fi

newDroolsVersion=$1
echo "New version is $newDroolsVersion"

newUberfireVersion=$2
echo "New Uberfire version is $newUberfireVersion"

startDateTime=`date +%s`

echo "droolsjbpmOrganizationDir is $droolsjbpmOrganizationDir"
cd $droolsjbpmOrganizationDir

echo "Maven home is ${mvnHome}"

for repository in `cat ${scriptDir}/../repository-list-csc.txt` ; do
    echo

    if [ ! -d $droolsjbpmOrganizationDir/$repository ]; then
      expectedPath=$droolsjbpmOrganizationDir/$repository
        echo "==============================================================================="
        echo "Missing Repository: $repository. SKIPPING!"
        echo "Expected path $expectedPath"
        echo "==============================================================================="
    else
        echo "==============================================================================="
        echo "Repository: $repository"
        echo "==============================================================================="
        cd $repository
        if [ $repository == 'droolsjbpm-build-bootstrap' ]; then
            # first build&install the current version (usually SNAPSHOT) as it is needed later by other repos
            '${mvnHome}/bin/mvn' -B -U -Dfull clean install
            '${mvnHome}/bin/mvn' -B -N -Dfull versions:set -DnewVersion=$newDroolsVersion -DallowSnapshots=true -DgenerateBackupPoms=false
            #sed -i "s/<version\.org\.kie>.*<\/version.org.kie>/<version.org.kie>$newDroolsVersion<\/version.org.kie>/" pom.xml
            sed -i "s/<version\.com\.csc>.*<\/version.com.csc>/<version.com.csc>$newDroolsVersion<\/version.com.csc>/" pom.xml
            sed -i "s/<version\.org\.uberfire>.*<\/version.org.uberfire>/<version.org.uberfire>$newUberfireVersion<\/version.org.uberfire>/" pom.xml
            sed -i "s/<version\.org\.uberfire\.extensions>.*<\/version.org.uberfire.extensions>/<version.org.uberfire.extensions>$newUberfireVersion<\/version.org.uberfire.extensions>/" pom.xml
            # update latest released version property only for non-SNAPSHOT versions
            if [[ ! $newDroolsVersion == *-SNAPSHOT ]]; then
                sed -i "s/<latestReleasedVersionFromThisBranch>.*<\/latestReleasedVersionFromThisBranch>/<latestReleasedVersionFromThisBranch>$newDroolsVersion<\/latestReleasedVersionFromThisBranch>/" pom.xml
            fi
            # workaround for http://jira.codehaus.org/browse/MVERSIONS-161
            '${mvnHome}/bin/mvn' -B clean install -DskipTests
            returnCode=$?

        elif [ $repository = 'jbpm' ]; then
            updateDroolsParentAndChildVersions
            returnCode=$?
            sed -i "s/release.version=.*$/release.version=$newDroolsVersion/" jbpm-installer/build.properties

        elif [ $repository = 'droolsjbpm-tools' ]; then
            cd drools-eclipse
            '${mvnHome}/bin/mvn' -B -Dfull tycho-versions:set-version -DnewVersion=$newDroolsVersion
            returnCode=$?
            # replace the leftovers not covered by the tycho plugin (bug?)
            # SNAPSHOT and release versions need to be handled differently
            versionToUse=$newDroolsVersion
            if [[ $newDroolsVersion == *-SNAPSHOT ]]; then
                versionToUse=`sed "s/-SNAPSHOT/.qualifier/" <<< $newDroolsVersion`
            fi
            sed -i "s/source_[^\"]*/source_$versionToUse/" org.drools.updatesite/category.xml
            sed -i "s/version=\"[^\"]*\">/version=\"$versionToUse\">/" org.drools.updatesite/category.xml
            cd ..
            if [ $returnCode == 0 ]; then
                '${mvnHome}/bin/mvn' -B -N clean install
                updateDroolsParentVersion
                # workaround for http://jira.codehaus.org/browse/MVERSIONS-161
                '${mvnHome}/bin/mvn' -B -N clean install -DskipTests
                cd drools-eclipse
                updateDroolsParentVersion
                cd ..
                updateDroolsChildModulesVersion
                returnCode=$?
            fi
        elif [ $repository = 'uberfire' ]; then
          # first build&install the current version (usually SNAPSHOT) as it is needed later by other repos
            '${mvnHome}/bin/mvn' -B -U -Dfull clean install -DskipTests
            '${mvnHome}/bin/mvn' -B -N -Dfull versions:set -DnewVersion=$newUberfireVersion -DallowSnapshots=true -DgenerateBackupPoms=false
            # workaround for http://jira.codehaus.org/browse/MVERSIONS-161
            '${mvnHome}/bin/mvn' -B clean install -DskipTests
            returnCode=$?
        elif [ $repository = 'uberfire-extensions' ]; then
            updateUberfireParentAndChildVersions
            '${mvnHome}/bin/mvn' -B clean install -DskipTests
            returnCode=$?
        elif [ $repository = 'csc-drools-extensions' ]; then
          # first build&install the current version (usually SNAPSHOT) as it is needed later by other repos
            '${mvnHome}/bin/mvn' -B -U -Dfull clean install -DskipTests
            '${mvnHome}/bin/mvn' -B -N -Dfull versions:set -DnewVersion=$newDroolsVersion -DallowSnapshots=true -DgenerateBackupPoms=false
            # workaround for http://jira.codehaus.org/browse/MVERSIONS-161
            '${mvnHome}/bin/mvn' -B clean install -DskipTests
            returnCode=$?
        else
            updateDroolsParentAndChildVersions
            returnCode=$?
        fi

        if [ $returnCode != 0 ] ; then
            exit $returnCode
        fi

        cd ..
    fi
done

endDateTime=`date +%s`
spentSeconds=`expr $endDateTime - $startDateTime`

echo
echo "Total time: ${spentSeconds}s"
