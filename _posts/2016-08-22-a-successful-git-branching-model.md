---
layout: post
title: "A successful Git branching model"
category: all-about-tech
date: 2016-08-22 18:27:57+00:00
---

<p>In this post I present the development model that I’ve introduced for all of my
projects (both at work and private) about a year ago, and which has turned out
to be very successful. I’ve been meaning to write about it for a while now, but
I’ve never really found the time to do so thoroughly, until now. I won’t talk
about any of the projects’ details, merely about the branching strategy and
release management.</p>

![image](http://nvie.com/img/git-model@2x.png)

<p>It focuses around <a href="http://git-scm.com">Git</a> as the tool for the versioning of
all of our source code.</p>
<h2>Why git?</h2>
<p>For a thorough discussion on the pros and cons of Git compared to centralized
source code control systems, <a href="http://whygitisbetterthanx.com/">see</a> the
<a href="http://git.or.cz/gitwiki/GitSvnComparsion">web</a>. There are plenty of flame
wars going on there. As a developer, I prefer Git above all other tools around
today. Git really changed the way developers think of merging and branching.
From the classic <span class="caps">CVS</span>/Subversion world I came from, merging/branching has
always been considered a bit scary (“beware of merge conflicts, they bite
you!”) and something you only do every once in a while.</p>
<p>But with Git, these actions are extremely cheap and simple, and they are
considered one of the core parts of your <em>daily</em> workflow, really. For example,
in <span class="caps">CVS</span>/Subversion <a href="http://svnbook.red-bean.com">books</a>, branching and merging is
first discussed in the later chapters (for advanced users), while in
<a href="http://book.git-scm.com">every</a>
<a href="http://pragprog.com/titles/tsgit/pragmatic-version-control-using-git">Git</a>
<a href="http://github.com/progit/progit">book</a>, it’s already covered in chapter 3
(basics).</p>
<p>As a consequence of its simplicity and repetitive nature, branching and merging
are no longer something to be afraid of. Version control tools are supposed to
assist in branching/merging more than anything else.</p>
<p>Enough about the tools, let’s head onto the development model.  The model that
I’m going to present here is essentially no more than a set of procedures that
every team member has to follow in order to come to a managed software
development process.</p>
<h2>Decentralized but centralized</h2>
<p>The repository setup that we use and that works well with this branching model,
is that with a central “truth” repo. Note that this repo is only <em>considered</em>
to be the central one (since Git is a <span class="caps">DVCS</span>, there is no such thing as a central
repo at a technical level). We will refer to this repo as <code>origin</code>, since this
name is familiar to all Git users.</p>

![image](http://nvie.com/img/centr-decentr@2x.png)

<p>Each developer pulls and pushes to origin. But besides the centralized
push-pull relationships, each developer may also pull changes from other peers
to form sub teams. For example, this might be useful to work together with two
or more developers on a big new feature, before pushing the work in progress to
<code>origin</code> prematurely. In the figure above, there are subteams of Alice and Bob,
Alice and David, and Clair and David.</p>
<p>Technically, this means nothing more than that Alice has defined a Git remote,
named <code>bob</code>, pointing to Bob’s repository, and vice versa.</p>
<h2>The main branches</h2>


![image](http://nvie.com/img/main-branches@2x.png)

<p>At the core, the development model is greatly inspired by existing models out
there. The central repo holds two main branches with an infinite lifetime:</p>
<ul>
<li><code>master</code></li>
	<li><code>develop</code></li>
</ul><p>The <code>master</code> branch at <code>origin</code> should be familiar to every Git user. Parallel
to the <code>master</code> branch, another branch exists called <code>develop</code>.</p>
<p>We consider <code>origin/master</code> to be the main branch where the source code of
<code>HEAD</code> always reflects a <em>production-ready</em> state.</p>
<p>We consider <code>origin/develop</code> to be the main branch where the source code of
<code>HEAD</code> always reflects a state with the latest delivered development changes
for the next release. Some would call this the “integration branch”. This is
where any automatic nightly builds are built from.</p>
<p>When the source code in the <code>develop</code> branch reaches a stable point and is
ready to be released, all of the changes should be merged back into <code>master</code>
somehow and then tagged with a release number. How this is done in detail will
be discussed further on.</p>
<p>Therefore, each time when changes are merged back into <code>master</code>, this is a new
production release <em>by definition</em>. We tend to be very strict at this, so that
theoretically, we could use a Git hook script to automatically build and
roll-out our software to our production servers everytime there was a commit on
<code>master</code>.</p>
<h2>Supporting branches</h2>
<p>Next to the main branches <code>master</code> and <code>develop</code>, our development model uses a
variety of supporting branches to aid parallel development between team
members, ease tracking of features, prepare for production releases and to
assist in quickly fixing live production problems. Unlike the main branches,
these branches always have a limited life time, since they will be removed
eventually.</p>
<p>The different types of branches we may use are:</p>
<ul>
<li>Feature branches</li>
	<li>Release branches</li>
	<li>Hotfix branches</li>
</ul><p>Each of these branches have a specific purpose and are bound to strict rules as
to which branches may be their originating branch and which branches must be
their merge targets. We will walk through them in a minute.</p>
<p>By no means are these branches “special” from a technical perspective. The
branch types are categorized by how we <em>use</em> them. They are of course plain old
Git branches.</p>
<h3>Feature branches</h3>
![image](http://nvie.com/img/fb@2x.png)
<p>May branch off from: <code>develop</code><br>
Must merge back into: <code>develop</code><br>
Branch naming convention: anything except <code>master</code>, <code>develop</code>, <code>release-*</code>,
or <code>hotfix-*</code></p>
<p>Feature branches (or sometimes called topic branches) are used to develop new
features for the upcoming or a distant future release. When starting
development of a feature, the target release in which this feature will be
incorporated may well be unknown at that point. The essence of a feature branch
is that it exists as long as the feature is in development, but will eventually
be merged back into <code>develop</code> (to definitely add the new feature to the
upcoming release) or discarded (in case of a disappointing experiment).</p>
<p>Feature branches typically exist in developer repos only, not in <code>origin</code>.</p>
<h4>Creating a feature branch</h4>
<p>When starting work on a new feature, branch off from the <code>develop</code> branch.</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout -b myfeature develop
<span class="go">Switched to a new branch "myfeature"</span></code></pre>
<h4>Incorporating a finished feature on develop</h4>
<p>Finished features may be merged into the <code>develop</code> branch definitely add them
to the upcoming release:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout develop
<span class="go">Switched to branch 'develop'</span>
<span class="gp">$</span> git merge --no-ff myfeature
<span class="go">Updating ea1b82a..05e9557</span>
<span class="go">(Summary of changes)</span>
<span class="gp">$</span> git branch -d myfeature
<span class="go">Deleted branch myfeature (was 05e9557).</span>
<span class="gp">$</span> git push origin develop</code></pre>
<p>The <code>--no-ff</code> flag causes the merge to always create a new commit object, even
if the merge could be performed with a fast-forward. This avoids losing
information about the historical existence of a feature branch and groups
together all commits that together added the feature. Compare:</p>

![image](http://nvie.com/img/merge-without-ff@2x.png)

<p>In the latter case, it is impossible to see from the Git history which of the
commit objects together have implemented a feature—you would have to manually
read all the log messages. Reverting a whole feature (i.e. a group of commits),
is a true headache in the latter situation, whereas it is easily done if the
<code>--no-ff</code> flag was used.</p>
<p>Yes, it will create a few more (empty) commit objects, but the gain is much
bigger that that cost.</p>
<p>Unfortunately, I have not found a way to make <code>--no-ff</code> the default behaviour
of <code>git merge</code> yet, but it really should be.</p>
<h3>Release branches</h3>
<p>May branch off from: <code>develop</code><br>
Must merge back into: <code>develop</code> and <code>master</code><br>
Branch naming convention: <code>release-*</code></p>
<p>Release branches support preparation of a new production release. They allow
for last-minute dotting of i’s and crossing t’s. Furthermore, they allow for
minor bug fixes and preparing meta-data for a release (version number, build
dates, etc.). By doing all of this work on a release branch, the <code>develop</code>
branch is cleared to receive features for the next big release.</p>
<p>The key moment to branch off a new release branch from <code>develop</code> is when
develop (almost) reflects the desired state of the new release. At least all
features that are targeted for the release-to-be-built must be merged in to
<code>develop</code> at this point in time. All features targeted at future releases may
not—they must wait until after the release branch is branched off.</p>
<p>It is exactly at the start of a release branch that the upcoming release gets
assigned a version number—not any earlier. Up until that moment, the <code>develop</code>
branch reflected changes for the “next release”, but it is unclear whether that
“next release” will eventually become 0.3 or 1.0, until the release branch is
started. That decision is made on the start of the release branch and is
carried out by the project’s rules on version number bumping.</p>
<h4>Creating a release branch</h4>
<p>Release branches are created from the <code>develop</code> branch. For example, say
version 1.1.5 is the current production release and we have a big release
coming up. The state of <code>develop</code> is ready for the “next release” and we have
decided that this will become version 1.2 (rather than 1.1.6 or 2.0). So we
branch off and give the release branch a name reflecting the new version
number:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout -b release-1.2 develop
<span class="go">Switched to a new branch "release-1.2"</span>
<span class="gp">$</span> ./bump-version.sh 1.2
<span class="go">Files modified successfully, version bumped to 1.2.</span>
<span class="gp">$</span> git commit -a -m <span class="s2">"Bumped version number to 1.2"</span>
<span class="go">[release-1.2 74d9424] Bumped version number to 1.2</span>
<span class="go">1 files changed, 1 insertions(+), 1 deletions(-)</span></code></pre>
<p>After creating a new branch and switching to it, we bump the version number.
Here, <code>bump-version.sh</code> is a fictional shell script that changes some files
in the working copy to reflect the new version. (This can of course be a manual
change—the point being that <em>some</em> files change.) Then, the bumped version
number is committed.</p>
<p>This new branch may exist there for a while, until the release may be rolled
out definitely. During that time, bug fixes may be applied in this branch
(rather than on the <code>develop</code> branch). Adding large new features here is
strictly prohibited. They must be merged into <code>develop</code>, and therefore, wait
for the next big release.</p>
<h4>Finishing a release branch</h4>
<p>When the state of the release branch is ready to become a real release, some
actions need to be carried out. First, the release branch is merged into
<code>master</code> (since every commit on <code>master</code> is a new release <em>by definition</em>,
remember). Next, that commit on <code>master</code> must be tagged for easy future
reference to this historical version. Finally, the changes made on the release
branch need to be merged back into <code>develop</code>, so that future releases also
contain these bug fixes.</p>
<p>The first two steps in Git:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout master
<span class="go">Switched to branch 'master'</span>
<span class="gp">$</span> git merge --no-ff release-1.2
<span class="go">Merge made by recursive.</span>
<span class="go">(Summary of changes)</span>
<span class="gp">$</span> git tag -a 1.2</code></pre>
<p>The release is now done, and tagged for future reference.<br><ins><strong>Edit:</strong> You might as well want to use the <code>-s</code> or <code>-u &lt;key&gt;</code> flags to sign
your tag cryptographically.</ins></p>
<p>To keep the changes made in the release branch, we need to merge those back
into <code>develop</code>, though. In Git:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout develop
<span class="go">Switched to branch 'develop'</span>
<span class="gp">$</span> git merge --no-ff release-1.2
<span class="go">Merge made by recursive.</span>
<span class="go">(Summary of changes)</span></code></pre>
<p>This step may well lead to a merge conflict (probably even, since we have
changed the version number). If so, fix it and commit.</p>
<p>Now we are really done and the release branch may be removed, since we don’t
need it anymore:</p>
<pre><code class="language-console"><span class="gp">$</span> git branch -d release-1.2
<span class="go">Deleted branch release-1.2 (was ff452fe).</span></code></pre>
<h3>Hotfix branches</h3>

![image](http://nvie.com/img/hotfix-branches@2x.png)

<p>May branch off from: <code>master</code><br>
Must merge back into: <code>develop</code> and <code>master</code><br>
Branch naming convention: <code>hotfix-*</code></p>
<p>Hotfix branches are very much like release branches in that they are also meant
to prepare for a new production release, albeit unplanned. They arise from the
necessity to act immediately upon an undesired state of a live production
version. When a critical bug in a production version must be resolved
immediately, a hotfix branch may be branched off from the corresponding tag on
the master branch that marks the production version.</p>
<p>The essence is that work of team members (on the <code>develop</code> branch) can
continue, while another person is preparing a quick production fix.</p>
<h4>Creating the hotfix branch</h4>
<p>Hotfix branches are created from the <code>master</code> branch. For example, say
version 1.2 is the current production release running live and causing troubles
due to a severe bug. But changes on <code>develop</code> are yet unstable. We may then
branch off a hotfix branch and start fixing the problem:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout -b hotfix-1.2.1 master
<span class="go">Switched to a new branch "hotfix-1.2.1"</span>
<span class="gp">$</span> ./bump-version.sh 1.2.1
<span class="go">Files modified successfully, version bumped to 1.2.1.</span>
<span class="gp">$</span> git commit -a -m <span class="s2">"Bumped version number to 1.2.1"</span>
<span class="go">[hotfix-1.2.1 41e61bb] Bumped version number to 1.2.1</span>
<span class="go">1 files changed, 1 insertions(+), 1 deletions(-)</span></code></pre>
<p>Don’t forget to bump the version number after branching off!</p>
<p>Then, fix the bug and commit the fix in one or more separate commits.</p>
<pre><code class="language-console"><span class="gp">$</span> git commit -m <span class="s2">"Fixed severe production problem"</span>
<span class="go">[hotfix-1.2.1 abbe5d6] Fixed severe production problem</span>
<span class="go">5 files changed, 32 insertions(+), 17 deletions(-)</span></code></pre>
<p><strong>Finishing a hotfix branch</strong></p>
<p>When finished, the bugfix needs to be merged back into <code>master</code>, but also needs
to be merged back into <code>develop</code>, in order to safeguard that the bugfix is
included in the next release as well. This is completely similar to how release
branches are finished.</p>
<p>First, update <code>master</code> and tag the release.</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout master
<span class="go">Switched to branch 'master'</span>
<span class="gp">$</span> git merge --no-ff hotfix-1.2.1
<span class="go">Merge made by recursive.</span>
<span class="go">(Summary of changes)</span>
<span class="gp">$</span> git tag -a 1.2.1</code></pre>
<p><ins><strong>Edit:</strong> You might as well want to use the <code>-s</code> or <code>-u &lt;key&gt;</code> flags to sign
your tag cryptographically.</ins></p>
<p>Next, include the bugfix in <code>develop</code>, too:</p>
<pre><code class="language-console"><span class="gp">$</span> git checkout develop
<span class="go">Switched to branch 'develop'</span>
<span class="gp">$</span> git merge --no-ff hotfix-1.2.1
<span class="go">Merge made by recursive.</span>
<span class="go">(Summary of changes)</span></code></pre>
<p>The one exception to the rule here is that, <strong>when a release branch currently
exists, the hotfix changes need to be merged into that release branch, instead
of <code>develop</code></strong>. Back-merging the bugfix into the release branch will
eventually result in the bugfix being merged into <code>develop</code> too, when the
release branch is finished. (If work in <code>develop</code> immediately requires this
bugfix and cannot wait for the release branch to be finished, you may safely
merge the bugfix into <code>develop</code> now already as well.)</p>
<p>Finally, remove the temporary branch:</p>
<pre><code class="language-console"><span class="gp">$</span> git branch -d hotfix-1.2.1
<span class="go">Deleted branch hotfix-1.2.1 (was abbe5d6).</span></code></pre>
<h2>Summary</h2>
<p>While there is nothing really shocking new to this branching model, the “big
picture” figure that this post began with has turned out to be tremendously
useful in our projects. It forms an elegant mental model that is easy to
comprehend and allows team members to develop a shared understanding of the
branching and releasing processes.</p>


source:[http://nvie.com/posts/a-successful-git-branching-model/](http://nvie.com/posts/a-successful-git-branching-model/)