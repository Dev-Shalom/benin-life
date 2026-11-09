// Adapter between the vehicle lab page and the shared vehicle library.
import type { BufferGeometry, ColorRepresentation } from 'three';
import { triCount, unitWheelGeometry, vehicleGeometry, vehicleKit, vehicleMaterial, type Lod, type VehicleModel } from '..';

export const LAB_MODELS = ['bike', 'moto', 'okada2', 'keke', 'hatch', 'sedan', 'sedan2', 'suv', 'suvlux', 'pickup', 'minibus', 'bus'];
export const labGeometry = (n: string, lod: number): BufferGeometry => vehicleGeometry(n as VehicleModel, lod as Lod);
export const labKit = (n: string, lod: number) => vehicleKit(n as VehicleModel, lod as Lod);
export const labMaterial = (c: ColorRepresentation) => vehicleMaterial(c);
export const labWheelGeometry = (style: string, lod: number) => unitWheelGeometry(style as 'car', lod as Lod);
export const labTris = triCount;
