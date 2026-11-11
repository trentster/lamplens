import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			// Every page becomes a plain file in build/, for GitHub Pages to serve.
			adapter: adapter({ pages: 'build', assets: 'build', fallback: undefined, precompress: false })
		})
	]
});
