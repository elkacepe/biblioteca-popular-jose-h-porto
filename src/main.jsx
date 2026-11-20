import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App.jsx';
import { AuthProvider } from './context/Auth.jsx';
import { BolsaProvider } from './context/Bolsa.jsx';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <BolsaProvider>
          <App />
        </BolsaProvider>
      </AuthProvider>
    </BrowserRouter>
  </React.StrictMode>,
);
