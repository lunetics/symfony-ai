# Fixture and container setup

How the app under test was built. The app was assembled interactively, so this is a
written procedure rather than a tested one-shot installer; the runtime facts below (image
digest, PHP and package versions) were read back from the running container and the lock
file.

## Container

Everything PHP runs inside one throwaway container. The agents stay on the host and reach
it through `docker exec`, which is deliberate: it reproduces the Docker/ddev case that is
still open in the upstream discussion, and it is the same indirection in every cell, so
arm comparisons stay valid.

```
image     composer:2
digest    sha256:b0fc12ea5130c8f68d0c676266dff7fc6969d34ef8ac00aed65a76f7a52b8db4
PHP       8.5.2 (NTS), Composer 2.9.5
user      1000:1000
mount     <MATE_EVAL_ROOT>/fixtures  ->  /fix
command   sleep infinity
```

One container per role in the original run: a build container that held the app skeleton
and a clone of the `symfony/ai` monorepo, and a runner container that mounts the fixture
copies and serves each of them with its own `php -S 127.0.0.1:<port> -t public`.

## The app under test

Symfony skeleton 8.1 with Doctrine ORM on SQLite, plus the web profiler. The full
dependency picture is in `fixture/composer-requirements.json`; the parts that matter:

- `symfony/ai-mate` and `symfony/ai-symfony-mate-extension` are installed from **path
  repositories** pointing into a checkout of the monorepo at the PR branch
  (`/ai/src/mate` and `/ai/src/mate/src/Bridge/Symfony`, `symlink: false`).
- Because the branch still declares `^0.12`, the requirement uses a branch alias:
  `"symfony/ai-mate": "dev-pr2380 as 0.12.99"`.
- The monorepo checkout was `git clone` of `symfony/ai` plus
  `git fetch origin pull/2380/head:pr2380`. The PR moved on during the study; the runs
  used commit `4e50aeb` of that branch.

## Seeding the N+1

`fixture/` holds the sources that were copied into the app:

- `src/Entity/Author.php` and `src/Entity/Book.php`: 20 authors, 5 books each, a plain
  lazy `ManyToOne` from book to author.
- `src/Controller/BookController.php`: `GET /books` iterates the books and touches
  `getAuthor()->getName()`, which is the N+1.
- `seed.php`: deterministic seeding, fixed names, no randomness.
- `env.local`: dev environment with the profiler enabled.
- `check-queries.php`: reads the profiler and prints `token=… url=… queries=N` for the
  last `/books` requests. This is the independent check for both the baseline and the fix.

The baseline is **21 queries**, not 101: Doctrine deduplicates authors within the request,
so it is one book query plus twenty author loads. Several models narrate "101 queries"
from reading the code alone; that mismatch is itself a signal, since the models that used
the profiler quoted the real number.

## Per-run discipline

Each fixture copy is its own git repository with a `snapshot` tag. Before every run:

1. `git reset --hard snapshot && git clean -fdx`. A plain reset to HEAD is not enough:
   agents sometimes commit their fix, which would silently move HEAD.
2. Reinstall the logging shim over `vendor/bin/mate`.
3. Warm the profiler with a couple of requests, then verify 21 queries **matched to a
   freshly issued debug token**. After a reset, `php -S` can serve a stale response for
   the first requests, so an unmatched count proves nothing.
4. Only then spawn the agent. Collect after the process exits plus a settle pause; an
   agent that writes after the reset would otherwise poison the next run.

Two more traps worth knowing: `composer` scripts that run `cache:clear` delete the
profiler data, and a copied fixture keeps absolute paths in the compiled Symfony
container, so `var/cache/dev` has to be rebuilt in the copy before it is trustworthy.
