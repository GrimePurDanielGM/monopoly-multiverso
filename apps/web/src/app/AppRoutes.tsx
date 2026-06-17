import { Route, Routes } from 'react-router-dom';
import { AppShell } from '../components/AppShell';
import { HomeScreen } from '../screens/HomeScreen';
import { CreateGameScreen } from '../screens/CreateGameScreen';
import { JoinScreen } from '../screens/JoinScreen';
import { LobbyScreen } from '../screens/LobbyScreen';
import { NotFoundScreen } from '../screens/NotFoundScreen';

/** Rutas de Fase 1. Separadas de App para poder montarlas con MemoryRouter en tests. */
export function AppRoutes() {
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="/" element={<HomeScreen />} />
        <Route path="/crear" element={<CreateGameScreen />} />
        <Route path="/unirse" element={<JoinScreen />} />
        <Route path="/j/:code" element={<JoinScreen />} />
        <Route path="/sala/:code" element={<LobbyScreen />} />
        <Route path="*" element={<NotFoundScreen />} />
      </Route>
    </Routes>
  );
}
