/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        tinta: { DEFAULT: '#21395B', 50: '#E9EDF3', 100: '#CDD6E3', 700: '#1A2E4A', 900: '#122036' },
        lacre: { DEFAULT: '#B23A32', 50: '#F7E4E2', 700: '#8F2E28' },
        papel: { DEFAULT: '#F4EBD9', 100: '#FAF5EB', 300: '#EADDC3', 400: '#DECBA6' },
        carbon: '#1C1C1C',
        mostaza: { DEFAULT: '#E0A83B', 50: '#FBF0D9' },
        pino: { DEFAULT: '#2F6B5E', 50: '#E1EEEA' },
      },
      fontFamily: {
        titulo: ['Bitter', 'Georgia', 'serif'],
        sans: ['"Source Sans 3"', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        papel: '0 1px 0 rgba(33,57,91,.08), 0 2px 6px rgba(33,57,91,.08)',
        sello: 'inset 0 0 0 2px currentColor',
      },
    },
  },
  plugins: [],
};
