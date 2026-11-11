<script lang="ts">
	import TextPage from '#lib/TextPage.svelte';
</script>

<svelte:head>
	<title>Privacy · Lamplens</title>
	<meta
		name="description"
		content="Lamplens never connects to the internet, not even once. There's nothing to sign in to, nothing to opt out of, and no one watching what you read."
	/>
</svelte:head>

<TextPage
	title="Privacy"
	lead="Lamplens never connects to the internet, not even once. There’s nothing to sign in to, nothing to opt out of, and no one watching what you read."
	contactLabel="Questions about privacy"
	lastUpdated="Last updated 11 November 2026. Changes to this policy appear on this page with a new date."
>
	{#snippet sections()}
		<h2>Lamplens collects no data</h2>
		<p>There’s no account, no analytics, no ads and no tracking. Your highlights, notes, bookmarks, searches and reading history are never sent to anyone.</p>

		<h2>What stays on your device</h2>
		<p>The app keeps your highlights, notes, bookmarks, reading position and settings on your device. They leave it only when you export or share them. Your iCloud or computer backups include them, as they do for any app.</p>

		<h2>The app never goes online</h2>
		<p>Everything is built in, including every translation and the reading voice. Lamplens works the same in flight mode as anywhere else.</p>

		<h2>Sharing and crash reports</h2>
		<p>When you share a verse or export your notes, it goes only where you send it. Apple passes crash reports to developers only if you’ve turned that on in your device’s settings, and they describe the crash, not your notes.</p>

		<h2>Children</h2>
		<p>The app collects nothing from anyone, children included.</p>

		<h2>This website</h2>
		<p>This website sets no cookies and runs no analytics. It’s hosted on GitHub Pages, which keeps standard server logs, including IP addresses, for security, as described in GitHub’s privacy statement.</p>
	{/snippet}
</TextPage>

<style>
	h2 {
		margin: 28px 0 0;
		font-weight: 500;
		font-size: var(--h2-text);
		line-height: 1.25;
		letter-spacing: -0.01em;
	}

	p {
		color: var(--ink);
	}
</style>
