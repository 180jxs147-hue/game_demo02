import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import Home from "@/pages/Home";
import Battle from "@/pages/Battle";
import Barracks from "@/pages/Barracks";

export default function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/battle" element={<Battle />} />
        <Route path="/barracks" element={<Barracks />} />
      </Routes>
    </Router>
  );
}
