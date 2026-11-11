<footer>
	<div class="row">
		<span class="name">Lamplens</span>
		<nav aria-label="Footer">
			<a href="/support/">Support</a>
			<a href="/privacy/">Privacy</a>
			<a href="mailto:support@lamplens.app">support@lamplens.app</a>
		</nav>
	</div>
</footer>

<style>
	footer {
		max-width: var(--container);
		margin: 0 auto;
		padding: 0 var(--gutter);
	}

	.row {
		border-top: 1px solid var(--rule);
		padding: 28px 0 44px;
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: 12px 24px;
		font-size: 16px;
	}

	.name {
		color: var(--ink);
		font-weight: 500;
		font-size: 18px;
	}

	nav {
		display: flex;
		flex-wrap: wrap;
		gap: 4px 28px;
		align-items: center;
	}

	nav a {
		text-decoration: none;
		padding: 10px 0;
		color: var(--ink-soft);
	}
</style>
