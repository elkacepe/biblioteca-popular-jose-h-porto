import { Navigate, Route, Routes } from 'react-router-dom';
import { LayoutCampo, LayoutPanel, LayoutPublico, RequiereRol } from './components/Layouts.jsx';
import Catalogo from './pages/publico/Catalogo.jsx';
import Libro from './pages/publico/Libro.jsx';
import Bolsa from './pages/publico/Bolsa.jsx';
import FeriasPublicas from './pages/publico/Ferias.jsx';
import Ingresar from './pages/publico/Ingresar.jsx';
import MisPedidos from './pages/comprador/MisPedidos.jsx';
import Inicio from './pages/gestion/Inicio.jsx';
import Donaciones from './pages/gestion/Donaciones.jsx';
import Lote from './pages/gestion/Lote.jsx';
import Deposito from './pages/gestion/Deposito.jsx';
import Pedidos from './pages/gestion/Pedidos.jsx';
import Ferias from './pages/gestion/Ferias.jsx';
import Feria from './pages/gestion/Feria.jsx';
import Mostrador from './pages/gestion/Mostrador.jsx';
import Reparto from './pages/gestion/Reparto.jsx';
import Devoluciones from './pages/gestion/Devoluciones.jsx';
import Rendiciones from './pages/gestion/Rendiciones.jsx';
import Informes from './pages/gestion/Informes.jsx';
import Ajustes from './pages/gestion/Ajustes.jsx';
import MisCajas from './pages/caja/MisCajas.jsx';
import CajaFeria from './pages/caja/CajaFeria.jsx';
import Cierre from './pages/caja/Cierre.jsx';
import MisRecorridos from './pages/reparto/MisRecorridos.jsx';
import Hoja from './pages/reparto/Hoja.jsx';
import Ticket from './pages/Ticket.jsx';

const BIBLIO = ['bibliotecaria'];
const STAFF = ['bibliotecaria', 'comision'];

export default function App() {
  return (
    <Routes>
      <Route element={<LayoutPublico />}>
        <Route index element={<Catalogo />} />
        <Route path="libro/:id" element={<Libro />} />
        <Route path="bolsa" element={<Bolsa />} />
        <Route path="ferias" element={<FeriasPublicas />} />
        <Route path="ingresar" element={<Ingresar modo="ingresar" />} />
        <Route path="registro" element={<Ingresar modo="registro" />} />
        <Route path="mis-pedidos" element={<RequiereRol roles={['comprador']}><MisPedidos /></RequiereRol>} />
      </Route>

      <Route path="panel" element={<RequiereRol roles={STAFF}><LayoutPanel /></RequiereRol>}>
        <Route index element={<Inicio />} />
        <Route path="informes" element={<Informes />} />
        <Route path="rendiciones" element={<Rendiciones />} />
        <Route path="donaciones" element={<RequiereRol roles={BIBLIO}><Donaciones /></RequiereRol>} />
        <Route path="donaciones/:id" element={<RequiereRol roles={BIBLIO}><Lote /></RequiereRol>} />
        <Route path="deposito" element={<RequiereRol roles={BIBLIO}><Deposito /></RequiereRol>} />
        <Route path="pedidos" element={<RequiereRol roles={BIBLIO}><Pedidos /></RequiereRol>} />
        <Route path="ferias" element={<RequiereRol roles={BIBLIO}><Ferias /></RequiereRol>} />
        <Route path="ferias/:id" element={<RequiereRol roles={BIBLIO}><Feria /></RequiereRol>} />
        <Route path="mostrador" element={<RequiereRol roles={BIBLIO}><Mostrador /></RequiereRol>} />
        <Route path="mostrador/cierre/:jornada" element={<RequiereRol roles={BIBLIO}><Cierre /></RequiereRol>} />
        <Route path="reparto" element={<RequiereRol roles={BIBLIO}><Reparto /></RequiereRol>} />
        <Route path="reparto/:id" element={<RequiereRol roles={BIBLIO}><Hoja /></RequiereRol>} />
        <Route path="devoluciones" element={<RequiereRol roles={BIBLIO}><Devoluciones /></RequiereRol>} />
        <Route path="ajustes" element={<RequiereRol roles={BIBLIO}><Ajustes /></RequiereRol>} />
      </Route>

      <Route path="caja" element={<RequiereRol roles={['caja', 'bibliotecaria']}><LayoutCampo /></RequiereRol>}>
        <Route index element={<MisCajas />} />
        <Route path="feria/:id" element={<CajaFeria />} />
        <Route path="feria/:id/cierre" element={<Cierre />} />
        <Route path="mostrador" element={<Mostrador campo />} />
        <Route path="mostrador/cierre/:jornada" element={<Cierre />} />
      </Route>

      <Route path="reparto" element={<RequiereRol roles={['repartidor']}><LayoutCampo /></RequiereRol>}>
        <Route index element={<MisRecorridos />} />
        <Route path=":id" element={<Hoja />} />
      </Route>

      <Route path="ticket/:id" element={<RequiereRol roles={['caja', 'bibliotecaria', 'comision', 'comprador']}><Ticket /></RequiereRol>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
