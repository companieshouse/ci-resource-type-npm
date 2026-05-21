const { promisify } = require('util');
const { execFile } = require('child_process');
const fs = require('fs-extra');
const os = require('os');
const path = require('path');
const tar = require('tar')
const RegClient = require('npm-registry-client')
const Readable = require('stream').Readable;

const request = require('request');
request.delete = promisify(request.delete);
request.get = promisify(request.get);
request.put = promisify(request.put);

const regClient = new RegClient();
regClient.get = promisify(regClient.get);
regClient.unpublish = promisify(regClient.unpublish);
regClient.publish = promisify(regClient.publish);
const execFileAsync = promisify(execFile);

const addRegistryToPackageJson = (json, registry = undefined) =>
    registry === undefined ? json : ({...json, "publishConfig": {
        "registry": registry
    }});

const unscopedPackageName = packageName => packageName.replace(/^.*\//, '');
const hasUserPassAuth = auth => auth && auth.username && auth.password;

const normalizeRegistryTarget = registry => `${registry || ''}`.replace(/^https?:/, '');

const writeAuthNpmrc = async (directory, registry, auth) => {
    const npmrcPath = path.join(directory, '.npmrc');
    const lines = [];

    if (registry) {
        lines.push(`registry=${registry}`);
    }

    const registryTarget = normalizeRegistryTarget(registry);
    if (auth && auth.token) {
        lines.push(`${registryTarget}:_authToken=${auth.token}`);
    } else if (auth && auth.username && auth.password) {
        const encodedPassword = Buffer.from(auth.password).toString('base64');
        lines.push(`${registryTarget}:username=${auth.username}`);
        lines.push(`${registryTarget}:_password=${encodedPassword}`);
        lines.push(`${registryTarget}:email=${auth.email || 'test@example.com'}`);
    }

    await fs.writeFile(npmrcPath, `${lines.join('\n')}\n`);
    return npmrcPath;
};

const npmWithAuth = async (registry, auth, args, cwd) => {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'npm-registry-util-'));
    const userConfig = await writeAuthNpmrc(tempRoot, registry, auth);
    try {
        return await execFileAsync('npm', args, {
            cwd,
            env: {
                ...process.env,
                NPM_CONFIG_USERCONFIG: userConfig,
                npm_config_loglevel: process.env.npm_config_loglevel || 'error'
            }
        });
    } finally {
        await fs.remove(tempRoot);
    }
};

const getPackageVersionsNpm = async (registry, auth, packageName) => {
    const result = await npmWithAuth(registry, auth, ['view', packageName, 'versions', '--json', '--registry', registry], process.cwd())
        .catch(() => ({ stdout: '' }));

    if (!result.stdout || `${result.stdout}`.trim() === '') return [];

    const parsed = JSON.parse(result.stdout);
    return Array.isArray(parsed) ? parsed : [parsed];
};

const unpublishNpmUser = async (registry, auth, packageName, version) =>
    npmWithAuth(registry, auth, ['unpublish', `${packageName}@${version}`, '--force', '--registry', registry], process.cwd())
        .catch(() => true);

const inventPackage = async (tempDirectory, packageName, version, registry = undefined) =>
    fs.mkdirs(tempDirectory)
        .then(() =>fs.writeFile(path.join(tempDirectory, 'package.json'), JSON.stringify(addRegistryToPackageJson({ name: packageName, version }, registry))))
        .then(() => fs.writeFile(path.join(tempDirectory, 'README.md'), 'this package is the result of a step in a test automation setup'))
        .then(() => ['package.json', 'README.md']);

const publishInventedPackage = async (tempDirectory, registry, auth, packageName, version) =>
    inventPackage(path.join(tempDirectory, unscopedPackageName(packageName)), packageName, version)
        .then(files => {
            if (hasUserPassAuth(auth)) {
                return npmWithAuth(
                    registry,
                    auth,
                    ['publish', '--registry', registry],
                    path.join(tempDirectory, unscopedPackageName(packageName))
                );
            }

            return regClient.publish(registry, {
                metadata: {
                    "name": packageName,
                    "version": version
                },
                access: 'public',
                body: new Readable().wrap(tar.c({
                    gzip: true,
                    cwd: tempDirectory
                }, [unscopedPackageName(packageName)])),
                ...requestOptions(auth)
            });
        });

const packageUrl = (registry, packageName) => `${registry}${packageName}`;

const requestOptions = auth => ({ auth, alwaysAuth: true });

const getPackageVersions = async (registry, auth, packageName) =>
    hasUserPassAuth(auth)
        ? getPackageVersionsNpm(registry, auth, packageName)
        : regClient.get(packageUrl(registry, packageName), requestOptions(auth))
            .then(response => Object.keys(response.versions))
            .catch(() => []);

const unpublishNpmToken = async (registry, auth, packageName, version) =>
    regClient.unpublish(
        packageUrl(registry, packageName),
        { version, ...requestOptions(auth) })
        .catch(error => {
            const text = `${error || ''}`;
            if (/no such package available|\b404\b/i.test(text)) {
                return true;
            }
            throw error;
        });

const unpublishWithRegistry = async (registry, auth, packageName, version) =>
    hasUserPassAuth(auth)
        ? unpublishNpmUser(registry, auth, packageName, version)
        : unpublishNpmToken(registry, auth, packageName, version);

const ensureUserAvailable = async (registry, auth) => {
    if (!hasUserPassAuth(auth)) return;

    const uri = `${registry || ''}`.replace(/\/$/, '');
    const url = `${uri}/-/user/org.couchdb.user:${encodeURIComponent(auth.username)}`;

    const result = await request.put({
        url,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
            name: auth.username,
            password: auth.password,
            email: auth.email || 'test@example.com',
            type: 'user'
        })
    }).catch(() => undefined);

    if (!result) return;

    if (![200, 201, 409].includes(result.statusCode)) {
        throw new Error(`failed to ensure registry user ${auth.username}: ${result.statusCode} ${result.body || ''}`);
    }

    if (!result.body) return;

    const body = typeof result.body === 'string'
        ? result.body
        : JSON.stringify(result.body);

    try {
        const parsed = JSON.parse(body);
        return parsed.token;
    } catch {
        return;
    }
};

const issueTokenFromUser = async registry => {
    const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const auth = {
        username: `token-user-${suffix}`,
        password: `token-pass-${suffix}`,
        email: `token-user-${suffix}@example.com`
    };

    const token = await ensureUserAvailable(registry, auth);
    if (!token) {
        throw new Error('failed to obtain token from registry user setup');
    }

    return token;
};

const ensurePackageVersionNotAvailable = async (registry, auth, packageName, packageVersion) =>
    getPackageVersions(registry, auth, packageName)
        .then(versions => versions.filter(version => version === packageVersion))
        .then(versions => versions.map(version => unpublishWithRegistry(registry, auth, packageName, version)))
        .then(promises => Promise.all(promises))

const ensurePackageVersionAvailable = async (tempDirectory, registry, auth, packageName, version) =>
    getPackageVersions(registry, auth, packageName)
        .then(versions => versions.filter(v => v === version).length > 0)
        .then(async packagePresent => packagePresent ? true :
            publishInventedPackage(tempDirectory, registry, auth, packageName, version));

module.exports = {
    ensurePackageVersionNotAvailable,
    ensurePackageVersionAvailable,
    inventPackage,
    getPackageVersions,
    ensureUserAvailable,
    issueTokenFromUser
};
